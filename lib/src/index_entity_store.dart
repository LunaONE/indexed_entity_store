import 'package:disposable_value_listenable/disposable_value_listenable.dart';
import 'package:flutter/foundation.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';
import 'package:sqlite3/sqlite3.dart';

part 'index_collector.dart';
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

  final Map<K, List<QueryResultMapping<dynamic>>> _singleEntityResults = {};

  final List<QueryResultMapping<dynamic>> _entityResults = [];

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
  /// they can use [query] with a `limit: 1` instead.
  QueryResult<T?> single({
    required QueryBuilder where,
  }) {
    final QueryResultMapping<T?> mapping = (
      () => _singleOnce(where: where),
      QueryResult._(
        initialValue: _singleOnce(where: where),
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
  T? singleOnce({
    required QueryBuilder where,
  }) {
    return _singleOnce(where: where).result;
  }

  MappedDBResult<T?> _singleOnce({
    required QueryBuilder where,
  }) {
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
      if (limit != null) ' LIMIT ?',
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
    try {
      _database.execute('BEGIN');
      assert(_database.autocommit == false);

      _entityInsertStatement.execute(
        [_entityKey, _connector.getPrimaryKey(e), _connector.serialize(e)],
      );
      _assertNoMoreIndexEntries(_connector.getPrimaryKey(e));

      _updateIndexInternal(e);

      _database.execute('COMMIT');
    } catch (e) {
      _database.execute('ROLLBACK');

      rethrow;
    }

    _handleUpdate({_connector.getPrimaryKey(e)});
  }

  /// Insert or update many entities in a single batch
  ///
  /// Notification for changes will only fire after all changes have been written (meaning queries will get a single update after all writes are finished)
  void writeMany(
    Iterable<T> entities, {
    bool singleStatement = true,
  }) {
    final keys = <K>{};

    final sw = Stopwatch()..start();

    if (singleStatement) {
      if (entities.isEmpty) {
        return;
      }

      try {
        _database.execute('BEGIN');

        _database.execute(
          [
            'REPLACE INTO `entity` (`type`, `key`, `value`) '
                ' VALUES (?1, ?, ?)',
            // Add additional entry values for each further parameter
            ', (?1, ?, ?)' * (entities.length - 1),
          ].join(' '),
          [
            _entityKey,
            for (final e in entities) ...[
              _connector.getPrimaryKey(e),
              _connector.serialize(e),
            ],
          ],
        );

        _updateIndexInternalSingleStatement(entities);

        _database.execute('COMMIT');
      } catch (e) {
        _database.execute('ROLLBACK');

        rethrow;
      }

      keys.addAll(entities.map(_connector.getPrimaryKey));
    } else {
      // transaction variant

      try {
        _database.execute('BEGIN');
        assert(_database.autocommit == false);

        for (final e in entities) {
          _entityInsertStatement.execute(
            [_entityKey, _connector.getPrimaryKey(e), _connector.serialize(e)],
          );

          _updateIndexInternal(e);

          keys.add(_connector.getPrimaryKey(e));
        }

        _database.execute('COMMIT');
      } catch (e) {
        _database.execute('ROLLBACK');

        rethrow;
      }
    }

    print(
        '$singleStatement ${(sw.elapsedMicroseconds / 1000).toStringAsFixed(2)}ms');

    _handleUpdate(keys);
  }

  late final _insertIndexStatement = _database.prepare(
    'INSERT INTO `index` (`type`, `entity`, `field`, `value`, `referenced_type`, `unique`) VALUES (?, ?, ?, ?, ?, ?)',
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
          indexColumn._referencedEntity,
          indexColumn._unique,
        ],
      );
    }
  }

  void _updateIndexInternalSingleStatement(Iterable<T> entities) {
    if (_indexColumns._indexColumns.values.isEmpty) {
      return;
    }

    _database.execute(
      [
        'INSERT INTO `index` (`type`, `entity`, `field`, `value`, `referenced_type`, `unique`) '
            ' VALUES (?1, ?, ?, ?, ?, ?)',
        // Add additional entry values for each further entity
        ', (?1, ?, ?, ?, ?, ?)' *
            (entities.length * _indexColumns._indexColumns.values.length - 1),
      ].join(' '),
      [
        _entityKey,
        for (final indexColumn in _indexColumns._indexColumns.values)
          for (final e in entities) ...[
            _connector.getPrimaryKey(e),
            indexColumn._field,
            indexColumn._getIndexValue(e),
            indexColumn._referencedEntity,
            indexColumn._unique,
          ],
      ],
    );
  }

  /// Delete the specified entries
  void delete({
    final T? entity,
    final Iterable<T>? entities,
    final K? key,
    final Iterable<K>? keys,
    final QueryBuilder? where,
    final bool? all,
  }) {
    assert(
      entity != null ||
          entities != null ||
          key != null ||
          keys != null ||
          where != null ||
          all != null,
    );
    assert(
      all == null ||
          (entity == null &&
              entities == null &&
              key == null &&
              keys == null &&
              where == null),
    );

    if (all == true) {
      _deleteAll();
    } else {
      final combinedKeys = {
        if (entity != null) _connector.getPrimaryKey(entity),
        ...?entities?.map(_connector.getPrimaryKey),
        if (key != null) key,
        ...?keys,
      };

      if (combinedKeys.isNotEmpty) {
        _deleteManyByKey(combinedKeys);
      }

      if (where != null) {
        _deleteWhere(where);
      }
    }
  }

  /// Removes all entries from the store
  void _deleteAll() {
    final result = _database.select(
      'DELETE FROM `entity` WHERE `type` = ? RETURNING `key`',
      [_entityKey],
    );

    _handleUpdate(
      {
        for (final row in result) row['key']! as K,
      },
    );
  }

  /// Deletes many entities by their primary key
  void _deleteManyByKey(Set<K> keys) {
    try {
      _database.execute('BEGIN');

      for (final key in keys) {
        _database.execute(
          'DELETE FROM `entity` WHERE `type` = ? AND `key` = ?',
          [_entityKey, key],
        );

        _assertNoMoreIndexEntries(key);
      }

      _database.execute('COMMIT');
    } catch (e) {
      _database.execute('ROLLBACK');

      rethrow;
    }

    _handleUpdate(keys);
  }

  /// Deletes entities matching the query
  void _deleteWhere(QueryBuilder query) {
    final Set<K> keys;

    try {
      _database.execute('BEGIN');

      final whereClause = query(_indexColumns)._entityKeysQuery();

      final result = _database.select(
        'DELETE FROM `entity` '
        ' WHERE `type` = ? '
        ' AND `entity`.`key` IN ( ${whereClause.$1} ) '
        ' RETURNING `key`',
        [
          _entityKey,
          ...whereClause.$2,
        ],
      );

      keys = {
        for (final row in result) row['key']! as K,
      };

      _database.execute('COMMIT');
    } catch (e) {
      _database.execute('ROLLBACK');

      rethrow;
    }

    _handleUpdate(keys);
  }

  void _assertNoMoreIndexEntries(K key) {
    assert(
      _database.select(
        'SELECT * FROM `index` WHERE `type` = ? and `entity` = ?',
        [_entityKey, key],
      ).isEmpty,
    );
  }

  void _ensureIndexIsUpToDate() {
    final List<({String field, bool usesUnique, bool usesReference})>
        currentDatabaseIndices = _database
            .select(
              'SELECT DISTINCT `field`, `unique` = 1 AS usesUnique, `referenced_type` IS NOT NULL AS usesReference FROM `index` WHERE `type` = ?',
              [this._entityKey],
            )
            .map(
              (row) => (
                field: row['field'] as String,
                usesUnique: row['usesUnique'] == 1,
                usesReference: row['usesReference'] == 1,
              ),
            )
            .toList();

    var needsIndexUpdate = false;
    if (currentDatabaseIndices.length != _indexColumns._indexColumns.length) {
      needsIndexUpdate = true;
    } else {
      for (final storeIndex in _indexColumns._indexColumns.values) {
        final databaseIndex = currentDatabaseIndices
            .where(
              (dbIndex) =>
                  dbIndex.field == storeIndex._field &&
                  dbIndex.usesReference ==
                      (storeIndex._referencedEntity != null) &&
                  dbIndex.usesUnique == storeIndex._unique,
            )
            .firstOrNull;

        if (databaseIndex == null) {
          debugPrint(
            'Index "${storeIndex._field}" (referencing "${storeIndex._referencedEntity}", unique "${storeIndex._unique}") was not found in the database and will now be created.',
          );

          needsIndexUpdate = true;
        }
      }
    }

    if (needsIndexUpdate) {
      try {
        _database.execute('BEGIN');

        _database.execute(
          'DELETE FROM `index` WHERE `type` = ?',
          [_entityKey],
        );

        final entities = queryOnce();

        for (final e in entities) {
          _updateIndexInternal(e);
        }

        _database.execute('COMMIT');

        debugPrint('Updated indices for ${entities.length} entities');
      } catch (e) {
        _database.execute('ROLLBACK');

        rethrow;
      }
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
                (e) => mapping.$2._value.value.dbValues[e.$1] == e.$2,
              )) {
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

/// Specifies how the result should be sorted
typedef OrderByClause = (String column, SortOrder direction);
