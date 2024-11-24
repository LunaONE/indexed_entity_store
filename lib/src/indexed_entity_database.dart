import 'package:flutter/foundation.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';
import 'package:sqlite3/sqlite3.dart';

class IndexedEntityDabase {
  factory IndexedEntityDabase.open(
    String path, {
    @visibleForTesting int targetSchemaVersion = 4,
  }) {
    return IndexedEntityDabase._(
      path,
      targetSchemaVersion: targetSchemaVersion,
    );
  }

  IndexedEntityDabase._(
    String path, {
    /// Up to which version the schema migrations should be run
    required int targetSchemaVersion,
  }) : _database = sqlite3.open(path) {
    final res = _database.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='entity';",
    );
    if (res.isEmpty) {
      debugPrint('Creating new DB');

      _initialDBSetup();
    }

    if (dbVersion < 2 && targetSchemaVersion >= 2) {
      _v2Migration();
    }

    if (dbVersion < 3 && targetSchemaVersion >= 3) {
      _v3Migration();
    }

    if (dbVersion < 4 && targetSchemaVersion >= 4) {
      _v4Migration();
    }

    assert(dbVersion == targetSchemaVersion);

    // Foreign keys need to be re-enable on every open (session)
    // https://www.sqlite.org/foreignkeys.html#fk_enable
    _database.execute('PRAGMA foreign_keys = ON');

    // Ensure that the library used actually supports foreign keys
    assert(
      _database.select('PRAGMA foreign_keys').first.values.first as int == 1,
    );
  }

  final Database _database;

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

  @visibleForTesting
  int get dbVersion => _database.select(
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

  void _v3Migration() {
    final res = _database.select(
      'DELETE FROM `index` WHERE NOT EXISTS (SELECT COUNT(*) FROM `entity` WHERE `entity`.`type` = type AND `entity`.`key` = entity) RETURNING `index`.`type`',
    );
    if (res.isNotEmpty) {
      debugPrint('Cleaned up ${res.length} unused indices');
    }

    _database.execute(
      'UPDATE `metadata` SET `value` = ? WHERE `key` = ?',
      [3, 'version'],
    );
  }

  void _v4Migration() {
    // New `index` table schema supporting unique and and foreign key constraints

    _database.execute('DROP TABLE `index`');

    _database.execute(
      'CREATE TABLE `index` ( '
      '  `type` TEXT NOT NULL, '
      '  `entity` NOT NULL, '
      '  `field` TEXT NOT NULL, '
      '  `value`, '
      '  `referenced_type` TEXT, '
      '  `unique` BOOLEAN NOT NULL DEFAULT FALSE, '
      '  FOREIGN KEY (`type`, `entity`) REFERENCES `entity` (`type`, `key`) ON DELETE CASCADE, '
      '  FOREIGN KEY (`referenced_type`, `value`) REFERENCES `entity` (`type`, `key`), '
      '  PRIMARY KEY ( `type`, `entity`, `field` )'
      ')',
    );

    _database.execute(
      'CREATE INDEX index_field_values '
      'ON `index` ( `type`, `field`, `value` )',
    );

    // This index is needed to not pay a performance penalty for the new foreign key constraint (between entities)
    // Otherwise the `writeMany` update duration would increase 5x (even without making use of the reference, passing `null`).
    // With this index, even though it only tracks non-`null` references (which would be rare), overall insert performance stays the same as before.
    _database.execute(
      'CREATE INDEX index_field_values_FK '
      'ON `index` ( `referenced_type`, `value` )'
      'WHERE `referenced_type` IS NOT NULL ',
    );

    _database.execute(
      'CREATE UNIQUE INDEX index_type_entity_field_unique_index '
      'ON `index` ( `type`, `field`, `value` ) '
      'WHERE `unique` = 1 ',
    );

    _database.execute(
      'UPDATE `metadata` SET `value` = ? WHERE `key` = ?',
      [4, 'version'],
    );
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

  void dispose() {
    _database.dispose();
  }
}
