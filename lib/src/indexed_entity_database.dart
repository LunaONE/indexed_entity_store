import 'package:flutter/foundation.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';
import 'package:sqlite3/sqlite3.dart';

class IndexedEntityDabase {
  final Database _database;

  IndexedEntityDabase._(String path) : _database = sqlite3.open(path) {
    final res = _database.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='entity';",
    );
    if (res.isEmpty) {
      debugPrint('Creating new DB');

      _initialDBSetup();
      _v2Migration();
    } else if (_dbVersion == 1) {
      debugPrint('Migrating DB to v2');

      _v2Migration();
    }

    assert(_dbVersion == 2);
  }

  void _initialDBSetup() {
    _database.execute('PRAGMA foreign_keys = ON');

    _database.execute(
      'CREATE TABLE `entity` ( `type` TEXT NOT NULL, `key` NOT NULL, `value`, PRIMARY KEY ( `type`, `key` ) )',
    );

    _database.execute(
      'CREATE TABLE `index` ( `type` TEXT NOT NULL, `entity` NOT NULL, `field` TEXT NOT NULL, `value`, '
      ' FOREIGN KEY (`type`, `entity`) REFERENCES `entity` (`type`, `key`) ON DELETE CASCADE'
      ')',
    );

    _database.execute(
      'CREATE INDEX index_field_values '
      'ON `index` ( `type`, `field`, `value` )',
    );

    _database.execute(
      'CREATE TABLE `metadata` ( `key` TEXT NOT NULL, `value` )',
    );

    _database.execute(
      'INSERT INTO `metadata` ( `key`, `value` ) VALUES ( ?, ? )',
      ['version', 1],
    );
  }

  int get _dbVersion => _database.select(
        'SELECT `value` FROM `metadata` WHERE `key` = ?',
        ['version'],
      ).single['value'] as int;

  void _v2Migration() {
    _database.execute(
      'CREATE UNIQUE INDEX index_type_entity_field_index '
      'ON `index` ( `type`, `entity`, `field` )',
    );

    _database.execute(
      'UPDATE `metadata` SET `value` = ? WHERE `key` = ?',
      [2, 'version'],
    );
  }

  factory IndexedEntityDabase.open(String path) {
    return IndexedEntityDabase._(path);
  }

  final _stores = <String, IndexedEntityStore>{};

  IndexedEntityStore<T, K> entityStore<T, K, S>(
    IndexedEntityConnector<T, K, S> connector,
  ) {
    if (_stores.containsKey(connector.entityKey)) {
      throw Exception(
        'A store for "${connector.entityKey}" has already been created',
      );
    }

    final store = IndexedEntityStore<T, K>(
      _database,
      connector,
    );

    _stores[connector.entityKey] = store;

    return store;
  }

  /// Closes the underlying database
  dispose() {
    _database.dispose();

    _stores.clear();
  }

  /// Updates the database in response to potential code changes after a hot reload
  /// Either have this method called in a high-level `State.reassemble` (before the database is used),
  /// or use the provided `IndexedEntityStoreHotReloadWrapper` widget.
  void handleHotReload() {
    for (final store in _stores.values) {
      store.init();
    }
  }
}
