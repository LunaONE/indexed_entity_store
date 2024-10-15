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
      final entity2 = _FooEntity(
        id: 2,
        valueA: 'something_else',
        valueB: 2,
        valueC: true,
      );
      fooStore.insert(entity2);

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
      fooStore.deleteEntity(entity2);

      expect(fooStore.subscriptionCount, 0);
    },
  );

  test(
    'Type-safe indices',
    () async {
      final path =
          '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

      final db = IndexedEntityDabase.open(path);

      final indexedEntityConnector =
          IndexedEntityConnector<_AllSupportedIndexTypes, String, String>(
        entityKey: 'indexed_entity',
        getPrimaryKey: (f) => f.string,
        getIndices: (index) {
          index((e) => e.string, as: 'string');
          index((e) => e.stringOpt, as: 'stringOpt');
          index((e) => e.number, as: 'number');
          index((e) => e.numberOpt, as: 'numberOpt');
          index((e) => e.integer, as: 'integer');
          index((e) => e.integerOpt, as: 'integerOpt');
          index((e) => e.float, as: 'float');
          index((e) => e.floatOpt, as: 'floatOpt');
          index((e) => e.boolean, as: 'boolean');
          index((e) => e.booleanOpt, as: 'booleanOpt');
          index((e) => e.dateTime, as: 'dateTime');
          index((e) => e.dateTimeOpt, as: 'dateTimeOpt');
        },
        serialize: (f) => jsonEncode(f.toJSON()),
        deserialize: (s) => _AllSupportedIndexTypes.fromJSON(
          jsonDecode(s) as Map<String, dynamic>,
        ),
      );

      final store = db.entityStore(indexedEntityConnector);

      expect(store.getAllOnce(), isEmpty);

      store.insert(
        _AllSupportedIndexTypes.defaultIfNull(string: 'default'),
      );
      store.insert(
        _AllSupportedIndexTypes.defaultIfNull(
          string: 'all_set',
          stringOpt: 'string_2',
          number: 1,
          numberOpt: 2,
          integer: 3,
          integerOpt: 4,
          float: 5.678,
          floatOpt: 6.789,
          boolean: false,
          booleanOpt: true,
          dateTime: DateTime.utc(2000),
          dateTimeOpt: DateTime.utc(2100),
        ),
      );

      expect(store.getAllOnce(), hasLength(2));

      // Valid queries with values
      expect(
        store.queryOnce((cols) => cols['string'].equals('all_set')),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['stringOpt'].equals('string_2')),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['number'].equals(1)),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['numberOpt'].equals(2)),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['integer'].equals(3)),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['integerOpt'].equals(4)),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['stringOpt'].equals('string_2')),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['float'].equals(5.678)),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['floatOpt'].equals(6.789)),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['boolean'].equals(false)),
        hasLength(2), //  as this also finds the default one
      );
      expect(
        store.queryOnce((cols) => cols['booleanOpt'].equals(true)),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['dateTime'].equals(DateTime.utc(2000))),
        hasLength(1),
      );
      expect(
        store.queryOnce(
          (cols) => cols['dateTimeOpt'].equals(DateTime.utc(2100)),
        ),
        hasLength(1),
      );

      // Valid queries with `null`
      expect(
        store.queryOnce((cols) => cols['stringOpt'].equals(null)),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['numberOpt'].equals(null)),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['integerOpt'].equals(null)),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['stringOpt'].equals(null)),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['floatOpt'].equals(null)),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['booleanOpt'].equals(null)),
        hasLength(1),
      );
      expect(
        store.queryOnce((cols) => cols['dateTimeOpt'].equals(null)),
        hasLength(1),
      );

      // type mismatches
      expect(
        () => store.queryOnce((cols) => cols['string'].equals(null)),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains(
              'Can not build query as field "string" needs a value of type String, but got Null.',
            ),
          ),
        ),
      );
      expect(
        () => store.queryOnce((cols) => cols['boolean'].equals(1.0)),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains(
              'Can not build query as field "boolean" needs a value of type bool, but got double.',
            ),
          ),
        ),
      );
      expect(
        () => store.queryOnce((cols) => cols['dateTime'].equals('')),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains(
              'Can not build query as field "dateTime" needs a value of type DateTime, but got String.',
            ),
          ),
        ),
      );
    },
  );

  test('Query operations', () async {
    final path = '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

    final db = IndexedEntityDabase.open(path);

    final indexedEntityConnector =
        IndexedEntityConnector<_AllSupportedIndexTypes, String, String>(
      entityKey: 'indexed_entity',
      getPrimaryKey: (f) => f.string,
      getIndices: (index) {
        index((e) => e.string, as: 'string');
        index((e) => e.stringOpt, as: 'stringOpt');
        index((e) => e.number, as: 'number');
        index((e) => e.numberOpt, as: 'numberOpt');
        index((e) => e.integer, as: 'integer');
        index((e) => e.integerOpt, as: 'integerOpt');
        index((e) => e.float, as: 'float');
        index((e) => e.floatOpt, as: 'floatOpt');
        index((e) => e.boolean, as: 'boolean');
        index((e) => e.booleanOpt, as: 'booleanOpt');
        index((e) => e.dateTime, as: 'dateTime');
        index((e) => e.dateTimeOpt, as: 'dateTimeOpt');
      },
      serialize: (f) => jsonEncode(f.toJSON()),
      deserialize: (s) => _AllSupportedIndexTypes.fromJSON(
        jsonDecode(s) as Map<String, dynamic>,
      ),
    );

    final store = db.entityStore(indexedEntityConnector);

    expect(store.getAllOnce(), isEmpty);

    final now = DateTime.now();

    store.insert(
      _AllSupportedIndexTypes.defaultIfNull(
        string: 'default',
        dateTime: now,
        float: 1000,
      ),
    );

    expect(
      store.queryOnce((cols) => cols['dateTime'].equals(now)),
      hasLength(1),
    );
    expect(
      store.queryOnce((cols) => cols['dateTime'].equals(now.toUtc())),
      hasLength(1),
    );

    expect(
      store.queryOnce((cols) => cols['dateTimeOpt'].equals(null)),
      hasLength(1),
    );

    // DateTime: less than, greater than
    expect(
      store.queryOnce((cols) => cols['dateTime'].lessThan(now)),
      isEmpty,
    );
    expect(
      store.queryOnce((cols) => cols['dateTime'].lessThanOrEqual(now)),
      hasLength(1),
    );
    expect(
      store.queryOnce((cols) => cols['dateTime'].greaterThan(now)),
      isEmpty,
    );
    expect(
      store.queryOnce((cols) => cols['dateTime'].greaterThanOrEqual(now)),
      hasLength(1),
    );
    expect(
      store.queryOnce(
        (cols) => cols['dateTime'].greaterThan(
          now.subtract(const Duration(seconds: 1)),
        ),
      ),
      hasLength(1),
    );

    // Null field: Should not be found for less than, equal, or greater than
    expect(
      store.queryOnce((cols) => cols['dateTimeOpt'].equals(now)),
      isEmpty,
    );
    expect(
      store.queryOnce((cols) => cols['dateTimeOpt'].lessThan(now)),
      isEmpty,
    );
    expect(
      store.queryOnce((cols) => cols['dateTimeOpt'].lessThanOrEqual(now)),
      isEmpty,
    );
    expect(
      store.queryOnce((cols) => cols['dateTimeOpt'].greaterThan(now)),
      isEmpty,
    );
    expect(
      store.queryOnce((cols) => cols['dateTimeOpt'].greaterThanOrEqual(now)),
      isEmpty,
    );

    /// Numeric
    expect(store.queryOnce((cols) => cols['float'].equals(1000)), hasLength(1));
    expect(
      store.queryOnce((cols) => cols['float'].greaterThan(1000)),
      isEmpty,
    );
    expect(
      store.queryOnce((cols) => cols['float'].greaterThan(999.6)),
      hasLength(1),
    );
    expect(
      store.queryOnce((cols) => cols['float'].greaterThanOrEqual(1000.0)),
      hasLength(1),
    );
  });
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

  /// not indexed
  final bool valueC;

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
  getIndices: (index) {
    index((e) => e.valueA, as: 'a');
    index((e) => e.valueB, as: 'b');
  },
  serialize: (f) => jsonEncode(f.toJSON()),
  deserialize: (s) => _FooEntity.fromJSON(
    jsonDecode(s) as Map<String, dynamic>,
  ),
);

final fooConnectorWithIndexOnC =
    IndexedEntityConnector<_FooEntity, int, String>(
  entityKey: fooConnector.entityKey,
  getPrimaryKey: fooConnector.getPrimaryKey,
  getIndices: (index) {
    index((e) => e.valueC, as: 'c');
  },
  serialize: fooConnector.serialize,
  deserialize: fooConnector.deserialize,
);

class _AllSupportedIndexTypes {
  final String string;
  final String? stringOpt;
  final num number;
  final num? numberOpt;
  final int integer;
  final int? integerOpt;
  final double float;
  final double? floatOpt;
  final bool boolean;
  final bool? booleanOpt;
  final DateTime dateTime;
  final DateTime? dateTimeOpt;

  _AllSupportedIndexTypes({
    required this.string,
    required this.stringOpt,
    required this.number,
    required this.numberOpt,
    required this.integer,
    required this.integerOpt,
    required this.float,
    required this.floatOpt,
    required this.boolean,
    required this.booleanOpt,
    required this.dateTime,
    required this.dateTimeOpt,
  });

  factory _AllSupportedIndexTypes.defaultIfNull({
    String? string,
    String? stringOpt,
    num? number,
    num? numberOpt,
    int? integer,
    int? integerOpt,
    double? float,
    double? floatOpt,
    bool? boolean,
    bool? booleanOpt,
    DateTime? dateTime,
    DateTime? dateTimeOpt,
  }) {
    return _AllSupportedIndexTypes(
      string: string ?? '',
      stringOpt: stringOpt,
      number: number ?? 0,
      numberOpt: numberOpt,
      integer: integer ?? 0,
      integerOpt: integerOpt,
      float: float ?? 0,
      floatOpt: floatOpt,
      boolean: boolean ?? false,
      booleanOpt: booleanOpt,
      dateTime: dateTime ?? DateTime.now(),
      dateTimeOpt: dateTimeOpt,
    );
  }

  Map<String, dynamic> toJSON() {
    return {
      'string': string,
      'stringOpt': stringOpt,
      'number': number,
      'numberOpt': numberOpt,
      'integer': integer,
      'integerOpt': integerOpt,
      'float': float,
      'floatOpt': floatOpt,
      'boolean': boolean,
      'booleanOpt': booleanOpt,
      'dateTime': dateTime.toIso8601String(),
      'dateTimeOpt': dateTimeOpt?.toIso8601String(),
    };
  }

  static _AllSupportedIndexTypes fromJSON(Map<String, dynamic> json) {
    return _AllSupportedIndexTypes(
      string: json['string'],
      stringOpt: json['stringOpt'],
      number: json['number'],
      numberOpt: json['numberOpt'],
      integer: json['integer'],
      integerOpt: json['integerOpt'],
      float: json['float'],
      floatOpt: json['floatOpt'],
      boolean: json['boolean'],
      booleanOpt: json['booleanOpt'],
      dateTime: DateTime.parse(json['dateTime']),
      dateTimeOpt: DateTime.tryParse(json['dateTimeOpt'] ?? ''),
    );
  }
}
