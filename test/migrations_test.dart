import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  test('Database migrations', () async {
    final path = '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

    // v1
    {
      final db = IndexedEntityDabase.open(path, targetSchemaVersion: 1);

      expect(db.dbVersion, 1);

      // can not open the store with the current code version, as index format differs

      db.dispose();
    }

    // v2
    {
      final db = IndexedEntityDabase.open(path, targetSchemaVersion: 2);

      expect(db.dbVersion, 2);

      // can not open the store with the current code version, as index format differs

      db.dispose();
    }

    // v3
    {
      final db = IndexedEntityDabase.open(path, targetSchemaVersion: 3);

      expect(db.dbVersion, 3);

      // can not open the store with the current code version, as index format differs

      db.dispose();
    }

    // v4
    {
      final db = IndexedEntityDabase.open(path, targetSchemaVersion: 4);

      expect(db.dbVersion, 4);

      final fooStore = db.entityStore(fooConnector);

      // The entity storage did not change, so we can use the normal write method to handle this
      fooStore.write(_FooEntity(id: 1, value: 'some value'));

      expect(
        fooStore.readOnce(1),
        isA<_FooEntity>().having((f) => f.value, 'value', 'some value'),
      );

      db.dispose();
    }

    File(path).deleteSync();
  });
}

class _FooEntity {
  _FooEntity({
    required this.id,
    required this.value,
  });

  final int id;

  final String value;

  Map<String, dynamic> toJSON() {
    return {
      'id': id,
      'value': value,
    };
  }

  static _FooEntity fromJSON(Map<String, dynamic> json) {
    return _FooEntity(
      id: json['id'],
      value: json['value'],
    );
  }
}

final fooConnector = IndexedEntityConnector<_FooEntity, int, String>(
  entityKey: 'foo',
  getPrimaryKey: (f) => f.id,
  getIndices: (index) {
    index((e) => e.value, as: 'value');
  },
  serialize: (f) => jsonEncode(f.toJSON()),
  deserialize: (s) => _FooEntity.fromJSON(
    jsonDecode(s) as Map<String, dynamic>,
  ),
);
