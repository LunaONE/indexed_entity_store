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
        'INSERT INTO `metadata` ( `key`, `value` ) VALUES ( "version" , 1)',
      );

      debugPrint('New DB created');
    }
  }

  factory IndexedEntityDabase.open(String path) {
    return IndexedEntityDabase._(path);
  }

  IndexedEntityStore<T, K> entityStore<T, K, S>(
    IndexedEntityConnector<T, K, S> connector,
  ) {
    // TODO(tp): Throw if another connected for `type` is already connect (taking reloads into account)

    return IndexedEntityStore<T, K>(
      _database,
      connector,
    );
  }

  dispose() {
    _database.dispose();
  }
}
