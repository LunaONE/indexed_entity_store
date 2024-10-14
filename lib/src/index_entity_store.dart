import 'package:flutter/foundation.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';
import 'package:sqlite3/sqlite3.dart';

part 'index_column.dart';
part 'index_columns.dart';
part 'query.dart';

class IndexedEntityStore<T, K> {
  IndexedEntityStore(this._database, this._connector) {
    _ensureIndexIsUpToDate();
  }

  final Database _database;

  final IndexedEntityConnector<T, K, dynamic> _connector;

  String get _entityKey => _connector.entityKey;

  T? get(K key) {
    final res = _database.select(
      'SELECT value FROM `entity` WHERE `type` = ? AND `key` = ?',
      [_entityKey, key],
    );

    if (res.isEmpty) {
      return null;
    }

    return _connector.deserialize(res.single['value']);
  }

  List<T> getAll() {
    final res = _database.select(
      'SELECT * FROM `entity` WHERE `type` = ?',
      [_entityKey],
    );

    return res.map((e) => _connector.deserialize(e['value'])).toList();
  }

  List<T> query(QueryBuilder q) {
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

  void delete(Set<K> keys) {
    for (final key in keys) {
      _database.execute(
        'DELETE FROM `entity` WHERE `type` = ? AND `key` = ?',
        [_entityKey, key],
      );
    }
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

      final entities = getAll();

      for (final e in entities) {
        _updateIndexInternal(e);
      }

      _database.execute('COMMIT');

      debugPrint('Updated indices for ${entities.length} entities');
    }
  }
}
