import 'package:flutter/foundation.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';
import 'package:sqlite3/sqlite3.dart';

part 'index_column.dart';
part 'index_columns.dart';
part 'query.dart';
part 'query_result.dart';

typedef QueryResultMapping<T> = (T Function(), QueryResult<T>);

class IndexedEntityStore<T, K> {
  IndexedEntityStore(this._database, this._connector) {
    _ensureIndexIsUpToDate();
  }

  final Database _database;

  final IndexedEntityConnector<T, K, dynamic> _connector;

  String get _entityKey => _connector.entityKey;

  final Map<K, List<QueryResultMapping>> _singleEntityResults = {};

  final List<QueryResultMapping> _entityResults = [];

  @visibleForTesting
  int get subscriptionCount =>
      _singleEntityResults.values.expand((mappings) => mappings).length +
      _entityResults.length;

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

  QueryResult<List<T>> getAll() {
    final QueryResultMapping<List<T>> mapping = (
      () => getAllOnce(),
      QueryResult._(
        initialValue: getAllOnce(),
        onDispose: (r) {
          _entityResults.removeWhere((m) => m.$2 != r);
        },
      )
    );

    _entityResults.add(mapping);

    return mapping.$2;
  }

  List<T> getAllOnce() {
    final res = _database.select(
      'SELECT * FROM `entity` WHERE `type` = ?',
      [_entityKey],
    );

    return res.map((e) => _connector.deserialize(e['value'])).toList();
  }

  QueryResult<List<T>> query(QueryBuilder q) {
    final QueryResultMapping<List<T>> mapping = (
      () => queryOnce(q),
      QueryResult._(
        initialValue: queryOnce(q),
        onDispose: (r) {
          _entityResults.removeWhere((m) => m.$2 != r);
        },
      )
    );

    _entityResults.add(mapping);

    return mapping.$2;
  }

  List<T> queryOnce(QueryBuilder q) {
    final columns = _connector.getIndices(null).keys.toList();

    final indexColumns = IndexColumns(
      {
        for (final column in columns)
          column: IndexColumn(
            entity: _entityKey,
            field: column,
          ),
      },
    );

    final (w, s) = q(indexColumns)._entityKeysQuery();

    final query =
        'SELECT value FROM `entity` WHERE `type` = ? AND `key` IN ( $w )';
    final values = [_entityKey, ...s];

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

    for (final MapEntry(:key, :value) in _connector.getIndices(e).entries) {
      _database.execute(
        'INSERT INTO `index` (`type`, `entity`, `field`, `value`) VALUES (?, ?, ?, ?)',
        [_entityKey, _connector.getPrimaryKey(e), key, value],
      );
    }
  }

  void delete(K key) {
    deleteMany({key});
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

    final currentEntityIndexedFields = _connector.getIndices(null).keys.toSet();

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
