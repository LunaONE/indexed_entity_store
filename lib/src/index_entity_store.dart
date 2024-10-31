import 'package:disposable_value_listenable/disposable_value_listenable.dart';
import 'package:flutter/foundation.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';
import 'package:sqlite3/sqlite3.dart';

part 'index_column.dart';
part 'index_columns.dart';
part 'query.dart';
part 'query_result.dart';

typedef QueryResultMapping<T> = (MappedDBResult<T> Function(), QueryResult<T>);

enum SortOrder {
  asc,
  desc,
}

class IndexedEntityStore<T, K> {
  IndexedEntityStore(
    this._database,
    this._connector,
  ) {
    {
      final collector = IndexCollector<T>._(_connector.entityKey);

      _connector.getIndices(collector);

      _indexColumns = IndexColumns._({
        for (final col in collector._indices) col._field: col,
      });
    }

    _ensureIndexIsUpToDate();
  }

  final Database _database;

  final IndexedEntityConnector<T, K, dynamic> _connector;

  late final IndexColumns _indexColumns;

  String get _entityKey => _connector.entityKey;

  final Map<K, List<QueryResultMapping>> _singleEntityResults = {};

  final List<QueryResultMapping> _entityResults = [];

  @visibleForTesting
  int get subscriptionCount {
    return _singleEntityResults.values.expand((mappings) => mappings).length +
        _entityResults.length;
  }

  /// Returns a subscription to a single entity by its primary key
  QueryResult<T?> read(K key) {
    final QueryResultMapping<T?> mapping = (
      () => _getOnce(key),
      QueryResult._(
        initialValue: _getOnce(key),
        onDispose: (r) {
          _singleEntityResults[key] = _singleEntityResults[key]!
              .where((mapping) => mapping.$2 != r)
              .toList();
        },
      )
    );

    _singleEntityResults.update(
      key,
      (mappings) => [...mappings, mapping],
      ifAbsent: () => [mapping],
    );

    return mapping.$2;
  }

  /// Returns a single entity by its primary key
  T? readOnce(K key) {
    return _getOnce(key).result;
  }

  MappedDBResult<T?> _getOnce(K key) {
    final res = _database.select(
      'SELECT value FROM `entity` WHERE `type` = ? AND `key` = ?',
      [_entityKey, key],
    );

    if (res.isEmpty) {
      return (dbValues: [null], result: null);
    }

    final dbValue = res.single['value'];

    return (dbValues: [dbValue], result: _connector.deserialize(dbValue));
  }

  /// Returns the single entity (or null) for the given query
  ///
  /// Throws an exception if the query returns 2 or more values.
  /// If the caller expects more than 1 value but is only interested in one,
  /// they can use [query] with a limit instead.
  QueryResult<T?> querySingle(QueryBuilder where) {
    final QueryResultMapping<T?> mapping = (
      () => _querySingleOnce(where),
      QueryResult._(
        initialValue: _querySingleOnce(where),
        onDispose: (r) {
          _entityResults.removeWhere((m) => m.$2 == r);
        },
      )
    );

    _entityResults.add(mapping);

    return mapping.$2;
  }

  /// Returns the single entity (or null) for the given query
  ///
  /// Throws an exception if the query returns 2 or more values.
  /// If the caller expects more than 1 value but is only interested in one,
  /// they can use [query] with a limit instead.
  T? querySingleOnce(QueryBuilder where) {
    return _querySingleOnce(where).result;
  }

  MappedDBResult<T?> _querySingleOnce(QueryBuilder where) {
    final result = _queryOnce(where: where, limit: 2);

    if (result.result.length > 1) {
      throw Exception(
        'singleOnce expected to find one element, but found at least 2 matching the query $where',
      );
    }

    return (dbValues: result.dbValues, result: result.result.firstOrNull);
  }

  /// Returns a subscription to entities matching the given query
  QueryResult<List<T>> query({
    QueryBuilder? where,
    OrderByClause? orderBy,
    int? limit,
  }) {
    final QueryResultMapping<List<T>> mapping = (
      () => _queryOnce(where: where, limit: limit, orderBy: orderBy),
      QueryResult._(
        initialValue: _queryOnce(where: where, limit: limit, orderBy: orderBy),
        onDispose: (r) {
          _entityResults.removeWhere((m) => m.$2 == r);
        },
      )
    );

    _entityResults.add(mapping);

    return mapping.$2;
  }

  /// Returns a list of entities matching the given query
  List<T> queryOnce({
    QueryBuilder? where,
    OrderByClause? orderBy,
    int? limit,
  }) {
    return _queryOnce(where: where, orderBy: orderBy, limit: limit).result;
  }

  MappedDBResult<List<T>> _queryOnce({
    QueryBuilder? where,
    OrderByClause? orderBy,
    int? limit,
  }) {
    final whereClause = where?.call(_indexColumns)._entityKeysQuery();

    final query = [
      'SELECT `entity`.`value` FROM `entity` ',
      if (orderBy != null)
        ' JOIN `index` ON `index`.`entity` = `entity`.`key` ',
      ' WHERE `entity`.`type` = ? ',
      if (whereClause != null) ' AND `entity`.`key` IN ( ${whereClause.$1} ) ',
      if (orderBy != null)
        'AND `index`.`field` = ? ORDER BY `index`.`value` ${orderBy.$2 == SortOrder.asc ? 'ASC' : 'DESC'}',
      if (limit != null) ' LIMIT ?'
    ].join();
    final values = [
      _entityKey,
      ...?whereClause?.$2,
      if (orderBy != null) orderBy.$1,
      if (limit != null) limit,
    ];

    final res = _database.select(query, values);

    final dbValues = res.map((e) => e['value']).toList();

    return (
      dbValues: dbValues,
      result: dbValues.map((v) => _connector.deserialize(v)).toList(),
    );
  }

  late final _entityInsertStatement = _database.prepare(
    'REPLACE INTO `entity` (`type`, `key`, `value`) VALUES (?, ?, ?)',
    persistent: true,
  );

  /// Insert or updates the given entity in the database.
  ///
  /// In case an entity with the same primary already exists in the database, it will be updated.
  // TODO(tp): We might want to rename this to `upsert` going forward to make it clear that this will overwrite and not error when the entry already exits (alternatively maybe `persist`, `write`, or `set`).
  void write(T e) {
    _database.execute('BEGIN');
    assert(_database.autocommit == false);

    _entityInsertStatement.execute(
      [_entityKey, _connector.getPrimaryKey(e), _connector.serialize(e)],
    );

    _updateIndexInternal(e);

    _database.execute('COMMIT');

    _handleUpdate({_connector.getPrimaryKey(e)});
  }

  /// Insert or update many entities in a single batch
  ///
  /// Notification for changes will only fire after all changes have been written (meaning queries will get a single update after all writes are finished)
  void writeMany(Iterable<T> entities) {
    _database.execute('BEGIN');
    assert(_database.autocommit == false);

    final keys = <K>{};
    for (final e in entities) {
      _entityInsertStatement.execute(
        [_entityKey, _connector.getPrimaryKey(e), _connector.serialize(e)],
      );

      _updateIndexInternal(e);

      keys.add(_connector.getPrimaryKey(e));
    }

    _database.execute('COMMIT');

    _handleUpdate(keys);
  }

  late final _insertIndexStatement = _database.prepare(
    'INSERT INTO `index` (`type`, `entity`, `field`, `value`) VALUES (?, ?, ?, ?)',
    persistent: true,
  );

  void _updateIndexInternal(T e) {
    for (final indexColumn in _indexColumns._indexColumns.values) {
      _insertIndexStatement.execute(
        [
          _entityKey,
          _connector.getPrimaryKey(e),
          indexColumn._field,
          indexColumn._getIndexValue(e),
        ],
      );
    }
  }

  /// Removes all entries from the store
  void deleteAll() {
    final result = _database.select(
      'DELETE FROM `entity` WHERE `type` = ? RETURNING `key`',
      [_entityKey],
    );

    _handleUpdate(
      {
        for (final row in result) row['key']!,
      },
    );
  }

  /// Deletes a single entity by its primary key
  void deleteByKey(K key) {
    deleteManyByKey({key});
  }

  /// Deletes a single entity
  void delete(T entity) {
    deleteByKey(_connector.getPrimaryKey(entity));
  }

  /// Deletes many entities
  void deleteMany(Iterable<T> entities) {
    deleteManyByKey(
      {
        for (final e in entities) _connector.getPrimaryKey(e),
      },
    );
  }

  /// Deletes many entities by their primary key
  void deleteManyByKey(Set<K> keys) {
    for (final key in keys) {
      _database.execute(
        'DELETE FROM `entity` WHERE `type` = ? AND `key` = ?',
        [_entityKey, key],
      );
    }

    _handleUpdate(keys);
  }

  void _ensureIndexIsUpToDate() {
    final currentlyIndexedFields = _database
        .select(
          'SELECT DISTINCT `field` FROM `index` WHERE `type` = ?',
          [this._entityKey],
        )
        .map((r) => r['field'] as String)
        .toSet();

    final currentEntityIndexedFields = _indexColumns._indexColumns.keys.toSet();

    final missingFields =
        currentEntityIndexedFields.difference(currentlyIndexedFields);

    if (currentEntityIndexedFields.length != currentlyIndexedFields.length ||
        missingFields.isNotEmpty) {
      debugPrint(
        'Need to update index as fields where changed or added',
      );

      _database.execute('BEGIN');

      final entities = queryOnce();

      for (final e in entities) {
        _updateIndexInternal(e);
      }

      _database.execute('COMMIT');

      debugPrint('Updated indices for ${entities.length} entities');
    }
  }

  void _handleUpdate(Set<K> keys) {
    for (final key in keys) {
      final singleEntitySubscriptions = _singleEntityResults[key];
      if (singleEntitySubscriptions != null) {
        for (final mapping in singleEntitySubscriptions) {
          final newValue = mapping.$1();

          if (newValue.dbValues.length ==
                  mapping.$2._value.value.dbValues.length &&
              newValue.dbValues.indexed.every(
                  (e) => mapping.$2._value.value.dbValues[e.$1] == e.$2)) {
            continue; // values already match
          }

          mapping.$2._value.value = newValue;
        }
      }
    }

    for (final mapping in _entityResults) {
      final newValue = mapping.$1();

      if (newValue.dbValues.length == mapping.$2._value.value.dbValues.length &&
          newValue.dbValues.indexed
              .every((e) => mapping.$2._value.value.dbValues[e.$1] == e.$2)) {
        continue; // values already match
      }

      mapping.$2._value.value = newValue;
    }
  }
}

// NOTE(tp): This is implemented as a `class` with `call` such that we can
// correctly capture the index type `I` and forward that to `IndexColumn`
class IndexCollector<T> {
  IndexCollector._(this._entityKey);

  final String _entityKey;

  final _indices = <IndexColumn<T, dynamic>>[];

  /// Adds a new index defined by the mapping [index] and stores it in [as]
  void call<I>(I Function(T e) index, {required String as}) {
    _indices.add(
      IndexColumn<T, I>._(
        entity: _entityKey,
        field: as,
        getIndexValue: index,
      ),
    );
  }
}

/// Specifies how the result should be sorted
typedef OrderByClause = (String column, SortOrder direction);
