import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  test('Database creation, write, and simple retrieval (*Once)', () async {
    final path = '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

    final db = IndexedEntityDabase.open(path);

    final fooStore = db.entityStore(fooConnector);

    expect(fooStore.getAllOnce(), isEmpty);

    fooStore.insert(
      _FooEntity(id: 99, valueA: 'a', valueB: 2, valueC: true),
    );

    expect(fooStore.getOnce(99), isA<_FooEntity>());
    expect(fooStore.getAllOnce(), hasLength(1));

    expect(fooStore.queryOnce((cols) => cols['a'].equals('a')), hasLength(1));
    expect(fooStore.queryOnce((cols) => cols['a'].equals('b')), hasLength(0));

    expect(fooStore.queryOnce((cols) => cols['b'].equals(2)), hasLength(1));
    expect(fooStore.queryOnce((cols) => cols['b'].equals(4)), hasLength(0));

    expect(
      fooStore.queryOnce((cols) => cols['a'].equals('a') & cols['b'].equals(2)),
      hasLength(1),
    );
    expect(
      fooStore.queryOnce((cols) => cols['a'].equals('b') & cols['b'].equals(2)),
      isEmpty,
    );
    expect(
      fooStore.queryOnce((cols) => cols['a'].equals('a') & cols['b'].equals(3)),
      isEmpty,
    );
    expect(
      fooStore.queryOnce((cols) => cols['a'].equals('b') & cols['b'].equals(3)),
      isEmpty,
    );

    expect(
      fooStore.queryOnce((cols) => cols['a'].equals('a') | cols['b'].equals(3)),
      hasLength(1),
    );
    expect(
      fooStore.queryOnce((cols) => cols['a'].equals('b') | cols['b'].equals(2)),
      hasLength(1),
    );
    expect(
      fooStore.queryOnce((cols) => cols['a'].equals('b') | cols['b'].equals(3)),
      isEmpty,
    );

    expect(
      () => fooStore.queryOnce((cols) => cols['does_not_exist'].equals('b')),
      throwsException,
    );

    // add a second entity with the same values, but different key
    fooStore.insert(
      _FooEntity(id: 101, valueA: 'a', valueB: 2, valueC: true),
    );

    expect(fooStore.getAllOnce(), hasLength(2));
    expect(fooStore.queryOnce((cols) => cols['a'].equals('a')), hasLength(2));

    // delete initial
    fooStore.deleteMany({99});
    expect(fooStore.getAllOnce(), hasLength(1));
    expect(fooStore.queryOnce((cols) => cols['a'].equals('a')), hasLength(1));

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

        expect(fooStore.getAllOnce(), isEmpty);

        fooStore.insert(
          _FooEntity(id: 99, valueA: 'a', valueB: 2, valueC: true),
        );

        expect(
          fooStore.queryOnce((cols) => cols['a'].equals('a')),
          hasLength(1),
        );
        expect(
          fooStore.queryOnce((cols) => cols['a'].equals('b')),
          hasLength(0),
        );

        fooStore.insert(
          _FooEntity(id: 99, valueA: 'A', valueB: 2, valueC: true),
        );
        expect(
          fooStore.queryOnce((cols) => cols['a'].equals('a')),
          hasLength(0),
        );
        expect(
          fooStore.queryOnce((cols) => cols['a'].equals('A')),
          hasLength(1),
        );
        expect(
          fooStore.queryOnce((cols) => cols['a'].equals('b')),
          hasLength(0),
        );

        db.dispose();
      }

      // setup with a new connect, which requires an index update
      {
        final db = IndexedEntityDabase.open(path);

        final fooStore = db.entityStore(fooConnectorWithIndexOnC);

        expect(fooStore.getAllOnce(), hasLength(1));
        // old index is not longer supported
        expect(
          () => fooStore.queryOnce((cols) => cols['a'].equals('A')),
          throwsException,
        );
        expect(
          fooStore.queryOnce((cols) => cols['c'].equals(true)),
          hasLength(1),
        );
      }

      File(path).delete();
    },
  );

  test(
    'Reactive queries',
    () async {
      final path =
          '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

      final db = IndexedEntityDabase.open(path);

      final fooStore = db.entityStore(fooConnector);

      final allFoos = fooStore.getAll();
      expect(allFoos.value, isEmpty);

      final fooById1 = fooStore.get(1);
      expect(fooById1.value, isNull);

      final fooByQueryValueA = fooStore.query((cols) => cols['a'].equals('a'));
      expect(fooByQueryValueA.value, isEmpty);

      final fooById99 = fooStore.get(99);
      expect(fooById99.value, isNull);

      final fooByQueryValueNotExists =
          fooStore.query((cols) => cols['a'].equals('does_not_exist'));
      expect(fooByQueryValueNotExists.value, isEmpty);

      // insert new entity matching the open queries
      fooStore.insert(
        _FooEntity(id: 1, valueA: 'a', valueB: 2, valueC: true),
      );

      expect(allFoos.value, hasLength(1));
      expect(fooById1.value, isA<_FooEntity>());
      expect(fooByQueryValueA.value, hasLength(1));
      expect(fooById99.value, isNull); // these 2 queries still return nothing
      expect(fooByQueryValueNotExists.value, isEmpty);

      // add another one only matching the _all_ query
      fooStore.insert(
        _FooEntity(id: 2, valueA: 'something_else', valueB: 2, valueC: true),
      );

      expect(allFoos.value, hasLength(2));
      expect(fooById1.value, isA<_FooEntity>());
      expect(fooByQueryValueA.value, hasLength(1));
      expect(fooById99.value, isNull); // these 2 queries still return nothing
      expect(fooByQueryValueNotExists.value, isEmpty);

      // delete ID 1
      fooStore.delete(1);
      expect(allFoos.value, hasLength(1));
      expect(fooById1.value, isNull);
      expect(fooByQueryValueA.value, isEmpty);
      expect(fooById99.value, isNull); // these 2 queries still return nothing
      expect(fooByQueryValueNotExists.value, isEmpty);

      /// Does not exist, does not make a difference
      fooStore.delete(9999);

      // Dispose all
      allFoos.dispose();
      fooById1.dispose();
      fooByQueryValueA.dispose();
      fooById99.dispose();
      fooByQueryValueNotExists.dispose();

      // No more subscriptions, so this has no effect
      fooStore.delete(2);

      expect(fooStore.subscriptionCount, 0);
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
