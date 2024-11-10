import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  test('Unique constraint test', () async {
    final path = '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

    final db = IndexedEntityDabase.open(path);

    // 2 separate store, each having a `value` and `uniqueValue` index
    final aStore = db.entityStore(aConnector);
    final bStore = db.entityStore(bConnector);

    final allAs = aStore.query();
    final allBs = bStore.query();

    // Each separate store may use the same unique value ("u")
    aStore.write(_Entity(id: 1, value: 'a', uniqueValue: 'u'));
    bStore.write(_Entity(id: 1, value: 'b', uniqueValue: 'u'));

    expect(allAs.value, hasLength(1));
    expect(allBs.value, hasLength(1));

    // Updating an entry works as expected (by primary key)
    aStore.write(_Entity(id: 1, value: 'new_a', uniqueValue: 'u'));
    expect(allAs.value.firstOrNull?.value, 'new_a');

    // Inserting a new entry which would use the same as an existing entry with a unique constraint errs
    expect(
      () => aStore.write(_Entity(id: 99, value: '', uniqueValue: 'u')),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('UNIQUE constraint failed'),
        ),
      ),
    );

    // When entry 1 releases the unique value, a new entry 2 can be written claiming it
    // Both entries can use the same value for the non-unique index in `value`
    aStore.write(_Entity(id: 1, value: 'a', uniqueValue: 'new_u'));
    aStore.write(_Entity(id: 2, value: 'a', uniqueValue: 'u'));
    expect(allAs.value, hasLength(2));

    allAs.dispose();
    allBs.dispose();
    db.dispose();

    File(path).deleteSync();
  });
}

class _Entity {
  _Entity({
    required this.id,
    required this.value,
    required this.uniqueValue,
  });

  final int id;

  final String value;

  final String uniqueValue;

  Map<String, dynamic> toJSON() {
    return {
      'id': id,
      'value': value,
      'uniqueValue': uniqueValue,
    };
  }

  static _Entity fromJSON(Map<String, dynamic> json) {
    return _Entity(
      id: json['id'],
      value: json['value'],
      uniqueValue: json['uniqueValue'],
    );
  }

  @override
  String toString() {
    return '_Entity($id, value: $value, uniqueValue: $uniqueValue)';
  }
}

final aConnector = IndexedEntityConnector<_Entity, int, String>(
  entityKey: 'a',
  getPrimaryKey: (f) => f.id,
  getIndices: (index) {
    index((e) => e.value, as: 'value');
    index((e) => e.uniqueValue, as: 'uniqueValue', unique: true);
  },
  serialize: (f) => jsonEncode(f.toJSON()),
  deserialize: (s) => _Entity.fromJSON(
    jsonDecode(s) as Map<String, dynamic>,
  ),
);

final bConnector = IndexedEntityConnector<_Entity, int, String>(
  entityKey: 'b',
  getPrimaryKey: (f) => f.id,
  getIndices: (index) {
    index((e) => e.value, as: 'value');
    index((e) => e.uniqueValue, as: 'uniqueValue', unique: true);
  },
  serialize: (f) => jsonEncode(f.toJSON()),
  deserialize: (s) => _Entity.fromJSON(
    jsonDecode(s) as Map<String, dynamic>,
  ),
);
