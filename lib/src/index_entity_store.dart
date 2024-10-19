import 'package:flutter/foundation.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';
import 'package:sqlite3/sqlite3.dart';

part 'index_column.dart';
part 'index_columns.dart';
part 'query.dart';
part 'query_result.dart';

typedef QueryResultMapping<T> = (T Function(), QueryResult<T>);

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
      final collector = IndexCollector<T>(_connector.entityKey);

      _connector.getIndices(collector);

      _indexColumns = IndexColumns({
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
  int get subscriptionCount =>
      _singleEntityResults.values.expand((mappings) => mappings).length +
      _entityResults.length;

  /// Returns a subscription to a single entity by its primary key
  QueryResult<T?> get(K key) {
    final QueryResultMapping<T?> mapping = (
      () => getOnce(key),
      QueryResult._(
        initialValue: getOnce(key),
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
  T? getOnce(K key) {
    final res = _database.select(
      'SELECT value FROM `entity` WHERE `type` = ? AND `key` = ?',
      [_entityKey, key],
    );

    if (res.isEmpty) {
      return null;
    }

    return _connector.deserialize(res.single['value']);
  }

  /// Returns a subscription to all entities in this store
  QueryResult<List<T>> getAll({
    OrderByClause? orderBy,
  }) {
    final QueryResultMapping<List<T>> mapping = (
      () => getAllOnce(orderBy: orderBy),
      QueryResult._(
        initialValue: getAllOnce(orderBy: orderBy),
        onDispose: (r) {
          _entityResults.removeWhere((m) => m.$2 != r);
        },
      )
    );

    _entityResults.add(mapping);

    return mapping.$2;
  }

  /// Returns a list of all entities in this store
  List<T> getAllOnce({
    OrderByClause? orderBy,
  }) {
    final res = _database.select(
      [
        'SELECT `entity`.`value` FROM `entity`',
        if (orderBy != null)
          ' JOIN `index` ON `index`.`entity` = `entity`.`key` ',
        ' WHERE `entity`.`type` = ? ',
        if (orderBy != null)
          ' AND `index`.`field` = ? ORDER BY `index`.`value` ${orderBy.$2 == SortOrder.asc ? 'ASC' : 'DESC'}',
      ].join(),
      [
        _entityKey,
        if (orderBy != null) orderBy.$1,
      ],
    );

    return res.map((e) => _connector.deserialize(e['value'])).toList();
  }

  /// Returns the single entity (or null) for the given query
  ///
  /// Throws an exception if the query returns 2 or more values.
  /// If the caller expects more than 1 value but is only interested in one,
  /// they can use [query] with a limit instead.
  QueryResult<T?> single(QueryBuilder q) {
    final QueryResultMapping<T?> mapping = (
      () => singleOnce(q),
      QueryResult._(
        initialValue: singleOnce(q),
        onDispose: (r) {
          _entityResults.removeWhere((m) => m.$2 != r);
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
  T? singleOnce(QueryBuilder q) {
    final result = queryOnce(q, limit: 2);

    if (result.length > 1) {
      throw Exception(
          'singleOnce expected to find one element, but found at least 2 matching the query $q');
    }

    return result.singleOrNull;
  }

  /// Returns a subscription to entities matching the given query
  QueryResult<List<T>> query(
    QueryBuilder q, {
    OrderByClause? orderBy,
    int? limit,
  }) {
    final QueryResultMapping<List<T>> mapping = (
      () => queryOnce(q, limit: limit, orderBy: orderBy),
      QueryResult._(
        initialValue: queryOnce(q, limit: limit, orderBy: orderBy),
        onDispose: (r) {
          _entityResults.removeWhere((m) => m.$2 != r);
        },
      )
    );

    _entityResults.add(mapping);

    return mapping.$2;
  }

  /// Returns a list of entities matching the given query
  List<T> queryOnce(
    QueryBuilder q, {
    OrderByClause? orderBy,
    int? limit,
  }) {
    final (w, s) = q(_indexColumns)._entityKeysQuery();

    final query = [
      'SELECT `entity`.`value` FROM `entity` ',
      if (orderBy != null)
        ' JOIN `index` ON `index`.`entity` = `entity`.`key` ',
      ' WHERE `entity`.`type` = ? AND `entity`.`key` IN ( $w ) ',
      if (orderBy != null)
        'AND `index`.`field` = ? ORDER BY `index`.`value` ${orderBy.$2 == SortOrder.asc ? 'ASC' : 'DESC'}',
      if (limit != null) ' LIMIT ?'
    ].join();
    final values = [
      _entityKey,
      ...s,
      if (orderBy != null) orderBy.$1,
      if (limit != null) limit,
    ];

    final res = _database.select(query, values);

    return res.map((e) => _connector.deserialize(e['value'])).toList();
  }

  void insert(T e) {
    _database.execute('BEGIN');
    assert(_database.autocommit == false);

    _database.execute(
      'REPLACE INTO `entity` (`type`, `key`, `value`) VALUES (?, ?, ?)',
      [_entityKey, _connector.getPrimaryKey(e), _connector.serialize(e)],
    );

    _updateIndexInternal(e);

    _database.execute('COMMIT');

    _handleUpdate({_connector.getPrimaryKey(e)});
  }

  void _updateIndexInternal(T e) {
    _database.execute(
      'DELETE FROM `index` WHERE `type` = ? AND `entity` = ?',
      [_entityKey, _connector.getPrimaryKey(e)],
    );

    for (final indexColumn in _indexColumns._indexColumns.values) {
      _database.execute(
        'INSERT INTO `index` (`type`, `entity`, `field`, `value`) VALUES (?, ?, ?, ?)',
        [
          _entityKey,
          _connector.getPrimaryKey(e),
          indexColumn._field,
          indexColumn._getIndexValue(e),
        ],
      );
    }
  }

  void delete(K key) {
    deleteMany({key});
  }

  void deleteEntity(T entity) {
    delete(_connector.getPrimaryKey(entity));
  }

  void deleteMany(Set<K> keys) {
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

      final entities = getAllOnce();

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
          mapping.$2._value.value = mapping.$1();
        }
      }
    }

    for (final mapping in _entityResults) {
      mapping.$2._value.value = mapping.$1();
    }
  }
}

class IndexCollector<T> {
  IndexCollector(this._entityKey);

  final String _entityKey;

  final _indices = <IndexColumn<T, dynamic>>[];

  void call<I>(I Function(T e) index, {required String as}) {
    _indices.add(
      IndexColumn<T, I>(
        entity: _entityKey,
        field: as,
        getIndexValue: index,
      ),
    );
  }
}

typedef OrderByClause = (String column, SortOrder direction);
