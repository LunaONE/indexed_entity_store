import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  test('Database creation, write, and simple retrieval', () async {
    final path = '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

    final db = IndexedEntityDabase.open(path);

    final fooStore = db.entityStore(fooConnector);

    expect(fooStore.getAll(), isEmpty);

    fooStore.insert(
      _FooEntity(id: 99, valueA: 'a', valueB: 2, valueC: true),
    );

    expect(fooStore.get(99), isA<_FooEntity>());
    expect(fooStore.getAll(), hasLength(1));

    expect(fooStore.query((cols) => cols['a'].equals('a')), hasLength(1));
    expect(fooStore.query((cols) => cols['a'].equals('b')), hasLength(0));

    expect(fooStore.query((cols) => cols['b'].equals(2)), hasLength(1));
    expect(fooStore.query((cols) => cols['b'].equals(4)), hasLength(0));

    expect(
      fooStore.query((cols) => cols['a'].equals('a') & cols['b'].equals(2)),
      hasLength(1),
    );
    expect(
      fooStore.query((cols) => cols['a'].equals('b') & cols['b'].equals(2)),
      isEmpty,
    );
    expect(
      fooStore.query((cols) => cols['a'].equals('a') & cols['b'].equals(3)),
      isEmpty,
    );
    expect(
      fooStore.query((cols) => cols['a'].equals('b') & cols['b'].equals(3)),
      isEmpty,
    );

    expect(
      fooStore.query((cols) => cols['a'].equals('a') | cols['b'].equals(3)),
      hasLength(1),
    );
    expect(
      fooStore.query((cols) => cols['a'].equals('b') | cols['b'].equals(2)),
      hasLength(1),
    );
    expect(
      fooStore.query((cols) => cols['a'].equals('b') | cols['b'].equals(3)),
      isEmpty,
    );

    expect(
      () => fooStore.query((cols) => cols['does_not_exist'].equals('b')),
      throwsException,
    );

    // add a second entity with the same values, but different key
    fooStore.insert(
      _FooEntity(id: 101, valueA: 'a', valueB: 2, valueC: true),
    );

    expect(fooStore.getAll(), hasLength(2));
    expect(fooStore.query((cols) => cols['a'].equals('a')), hasLength(2));

    // delete initial
    fooStore.delete({99});
    expect(fooStore.getAll(), hasLength(1));
    expect(fooStore.query((cols) => cols['a'].equals('a')), hasLength(1));

    db.dispose();

    File(path).delete();
  });

  test(
    'Entity index updates (values and columns)',
    () async {
      final path =
          '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

      // initial setup
      {
        final db = IndexedEntityDabase.open(path);

        final fooStore = db.entityStore(fooConnector);

        expect(fooStore.getAll(), isEmpty);

        fooStore.insert(
          _FooEntity(id: 99, valueA: 'a', valueB: 2, valueC: true),
        );

        expect(fooStore.query((cols) => cols['a'].equals('a')), hasLength(1));
        expect(fooStore.query((cols) => cols['a'].equals('b')), hasLength(0));

        fooStore.insert(
          _FooEntity(id: 99, valueA: 'A', valueB: 2, valueC: true),
        );
        expect(fooStore.query((cols) => cols['a'].equals('a')), hasLength(0));
        expect(fooStore.query((cols) => cols['a'].equals('A')), hasLength(1));
        expect(fooStore.query((cols) => cols['a'].equals('b')), hasLength(0));

        db.dispose();
      }

      // setup with a new connect, which requires an index update
      {
        final db = IndexedEntityDabase.open(path);

        final fooStore = db.entityStore(fooConnectorWithIndexOnC);

        expect(fooStore.getAll(), hasLength(1));
        // old index is not longer supported
        expect(
          () => fooStore.query((cols) => cols['a'].equals('A')),
          throwsException,
        );
        expect(fooStore.query((cols) => cols['c'].equals(true)), hasLength(1));
      }

      File(path).delete();
    },
  );
}

class _FooEntity {
  _FooEntity({
    required this.id,
    required this.valueA,
    required this.valueB,
    required this.valueC,
  });

  final int id;

  /// indexed via `a`
  final String valueA;

  /// indexed via "b"
  final int valueB;

  /// indexed
  final bool valueC;

  static Map<String, dynamic> indices(_FooEntity? f) => {
        'a': f?.valueA,
        "b": f?.valueB,
      };

  Map<String, dynamic> toJSON() {
    return {
      'id': id,
      'valueA': valueA,
      'valueB': valueB,
      'valueC': valueC,
    };
  }

  static _FooEntity fromJSON(Map<String, dynamic> json) {
    return _FooEntity(
      id: json['id'],
      valueA: json['valueA'],
      valueB: json['valueB'],
      valueC: json['valueC'],
    );
  }
}

final fooConnector = IndexedEntityConnector<_FooEntity, int, String>(
  entityKey: 'foo',
  getPrimaryKey: (f) => f.id,
  getIndices: (f) => _FooEntity.indices(f),
  serialize: (f) => jsonEncode(f.toJSON()),
  deserialize: (s) => _FooEntity.fromJSON(
    jsonDecode(s) as Map<String, dynamic>,
  ),
);

final fooConnectorWithIndexOnC =
    IndexedEntityConnector<_FooEntity, int, String>(
  entityKey: fooConnector.entityKey,
  getPrimaryKey: fooConnector.getPrimaryKey,
  getIndices: (f) => {
    'c': f?.valueC,
  },
  serialize: fooConnector.serialize,
  deserialize: fooConnector.deserialize,
);
