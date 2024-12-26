import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

    expect(fooStore.queryOnce(), isEmpty);

    fooStore.write(
      _FooEntity(id: 99, valueA: 'a', valueB: 2, valueC: true),
    );

    expect(fooStore.readOnce(99), isA<_FooEntity>());
    expect(fooStore.queryOnce(), hasLength(1));

    expect(
      fooStore.queryOnce(where: (cols) => cols['a'].equals('a')),
      hasLength(1),
    );
    // equals is case sensitive
    expect(
      fooStore.queryOnce(where: (cols) => cols['a'].equals('A')),
      isEmpty,
    );
    expect(
      fooStore.queryOnce(where: (cols) => cols['a'].equals('b')),
      hasLength(0),
    );

    expect(
      fooStore.queryOnce(where: (cols) => cols['b'].equals(2)),
      hasLength(1),
    );
    expect(
      fooStore.queryOnce(where: (cols) => cols['b'].equals(4)),
      hasLength(0),
    );

    expect(
      fooStore.queryOnce(
        where: (cols) => cols['a'].equals('a') & cols['b'].equals(2),
      ),
      hasLength(1),
    );
    expect(
      fooStore.queryOnce(
        where: (cols) => cols['a'].equals('b') & cols['b'].equals(2),
      ),
      isEmpty,
    );
    expect(
      fooStore.queryOnce(
        where: (cols) => cols['a'].equals('a') & cols['b'].equals(3),
      ),
      isEmpty,
    );
    expect(
      fooStore.queryOnce(
        where: (cols) => cols['a'].equals('b') & cols['b'].equals(3),
      ),
      isEmpty,
    );

    expect(
      fooStore.queryOnce(
        where: (cols) => cols['a'].equals('a') | cols['b'].equals(3),
      ),
      hasLength(1),
    );
    expect(
      fooStore.queryOnce(
        where: (cols) => cols['a'].equals('b') | cols['b'].equals(2),
      ),
      hasLength(1),
    );
    expect(
      fooStore.queryOnce(
        where: (cols) => cols['a'].equals('b') | cols['b'].equals(3),
      ),
      isEmpty,
    );

    expect(
      () => fooStore.queryOnce(
        where: (cols) => cols['does_not_exist'].equals('b'),
      ),
      throwsException,
    );

    // add a second entity with the same values, but different key
    fooStore.write(
      _FooEntity(id: 101, valueA: 'a', valueB: 2, valueC: true),
    );

    expect(fooStore.queryOnce(), hasLength(2));
    expect(
      fooStore.queryOnce(where: (cols) => cols['a'].equals('a')),
      hasLength(2),
    );

    // add a third entity with different values
    fooStore.write(
      _FooEntity(id: 999, valueA: 'aaa', valueB: 22, valueC: true),
    );

    expect(
      fooStore.queryOnce(where: (cols) => cols['b'].greaterThanOrEqual(2)),
      hasLength(3),
    );
    expect(
      fooStore.queryOnce(
        where: (cols) => cols['b'].greaterThan(2) & cols['b'].lessThan(22),
      ),
      isEmpty,
    );
    expect(
      fooStore.queryOnce(
        where: (cols) => cols['b'].greaterThan(1) & cols['b'].lessThan(22),
      ),
      hasLength(2),
    );
    expect(
      fooStore.queryOnce(
        where: (cols) =>
            cols['b'].greaterThan(1) & cols['b'].lessThanOrEqual(22),
      ),
      hasLength(3),
    );
    expect(
      fooStore.queryOnce(
        where: (cols) =>
            cols['b'].greaterThan(2) & cols['b'].lessThanOrEqual(22),
      ),
      hasLength(1),
    );
    expect(
      fooStore.queryOnce(
        where: (cols) => cols['b'].greaterThan(2),
      ),
      hasLength(1),
    );

    // delete initial & latest
    fooStore.delete(keys: [99, 999]);
    expect(fooStore.queryOnce(), hasLength(1));
    expect(
      fooStore.queryOnce(where: (cols) => cols['a'].equals('a')),
      hasLength(1),
    );

    db.dispose();

    File(path).deleteSync();
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

        expect(fooStore.queryOnce(), isEmpty);

        fooStore.write(
          _FooEntity(id: 99, valueA: 'a', valueB: 2, valueC: true),
        );

        expect(
          fooStore.queryOnce(where: (cols) => cols['a'].equals('a')),
          hasLength(1),
        );
        expect(
          fooStore.queryOnce(where: (cols) => cols['a'].equals('b')),
          hasLength(0),
        );

        fooStore.write(
          _FooEntity(id: 99, valueA: 'A', valueB: 2, valueC: true),
        );
        expect(
          fooStore.queryOnce(where: (cols) => cols['a'].equals('a')),
          hasLength(0),
        );
        expect(
          fooStore.queryOnce(where: (cols) => cols['a'].equals('A')),
          hasLength(1),
        );
        expect(
          fooStore.queryOnce(where: (cols) => cols['a'].equals('b')),
          hasLength(0),
        );

        db.dispose();
      }

      // setup with a new connector, which requires an index update
      {
        final db = IndexedEntityDabase.open(path);

        final fooStore = db.entityStore(fooConnectorWithIndexOnBAndC);

        expect(fooStore.queryOnce(), hasLength(1));
        // old index is not longer supported
        expect(
          () => fooStore.queryOnce(where: (cols) => cols['a'].equals('A')),
          throwsException,
        );
        expect(
          fooStore.queryOnce(where: (cols) => cols['b'].equals(1002)),
          hasLength(1),
        );
        expect(
          fooStore.queryOnce(where: (cols) => cols['b'].equals(1002)),
          hasLength(1),
        );
        expect(
          fooStore.queryOnce(where: (cols) => cols['c'].equals(true)),
          hasLength(1),
        );
      }

      // setup with a new connector (with unique index on B), which requires an index update
      {
        final db = IndexedEntityDabase.open(path);

        final fooStore =
            db.entityStore(fooConnectorWithUniqueIndexOnBAndIndexOnC);

        expect(fooStore.queryOnce(), hasLength(1));
        // old index is not longer supported
        expect(
          () => fooStore.queryOnce(where: (cols) => cols['a'].equals('A')),
          throwsException,
        );
        expect(
          fooStore.queryOnce(where: (cols) => cols['b'].equals(1002)),
          hasLength(1),
        );
        expect(
          fooStore.queryOnce(where: (cols) => cols['b'].equals(1002)),
          hasLength(1),
        );
        expect(
          fooStore.queryOnce(where: (cols) => cols['c'].equals(true)),
          hasLength(1),
        );
      }

      File(path).deleteSync();
    },
  );

  test(
    'Reactive queries',
    () async {
      final path =
          '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

      final db = IndexedEntityDabase.open(path);

      final fooStore = db.entityStore(fooConnector);

      final allFoos = fooStore.query();
      expect(allFoos.value, isEmpty);
      expect(fooStore.subscriptionCount, 1);

      const int singleId = -2263796707128;
      final fooById1 = fooStore.read(singleId);
      expect(fooById1.value, isNull);
      expect(fooStore.subscriptionCount, 2);

      final fooByQueryValueA =
          fooStore.query(where: (cols) => cols['a'].equals('a'));
      expect(fooByQueryValueA.value, isEmpty);

      final fooById99 = fooStore.read(99);
      expect(fooById99.value, isNull);

      final fooByQueryValueNotExists = fooStore.query(
        where: (cols) => cols['a'].equals('does_not_exist'),
      );
      expect(fooByQueryValueNotExists.value, isEmpty);

      // insert new entity matching the open queries
      fooStore.write(
        _FooEntity(id: singleId, valueA: 'a', valueB: 2, valueC: true),
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
      fooStore.write(entity2);

      expect(allFoos.value, hasLength(2));
      expect(fooById1.value, isA<_FooEntity>());
      expect(fooByQueryValueA.value, hasLength(1));
      expect(fooById99.value, isNull); // these 2 queries still return nothing
      expect(fooByQueryValueNotExists.value, isEmpty);

      // delete ID 1
      fooStore.delete(key: singleId);
      expect(allFoos.value, hasLength(1));
      expect(fooById1.value, isNull);
      expect(fooByQueryValueA.value, isEmpty);
      expect(fooById99.value, isNull); // these 2 queries still return nothing
      expect(fooByQueryValueNotExists.value, isEmpty);

      /// Does not exist, does not make a difference
      fooStore.delete(key: 9999);

      // Dispose all
      expect(fooStore.subscriptionCount, 5);
      allFoos.dispose();
      expect(fooStore.subscriptionCount, 4);
      fooById1.dispose();
      expect(fooStore.subscriptionCount, 3);
      fooByQueryValueA.dispose();
      expect(fooStore.subscriptionCount, 2);
      fooById99.dispose();
      expect(fooStore.subscriptionCount, 1);
      fooByQueryValueNotExists.dispose();
      expect(fooStore.subscriptionCount, 0);

      // No more subscriptions, so this has no effect
      fooStore.delete(entity: entity2);
    },
  );

  test(
    'Reactive queries, check against duplicate updates',
    () {
      final path =
          '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

      final db = IndexedEntityDabase.open(path);

      final valueWrappingConnector =
          IndexedEntityConnector<_ValueWrapper, int, String>(
        entityKey: 'value_wrapper',
        getPrimaryKey: (f) => f.key,
        getIndices: (index) {
          index((e) => e.value.length, as: 'length');
        },
        serialize: (f) => jsonEncode(f.toJSON()),
        deserialize: (s) => _ValueWrapper.fromJSON(
          jsonDecode(s) as Map<String, dynamic>,
        ),
      );

      final valueStore = db.entityStore(valueWrappingConnector);

      final valueWithId1Subscription = valueStore.read(1);
      final valuesWithId1 = [valueWithId1Subscription.value];
      valueWithId1Subscription.addListener(() {
        // Add new values as they are exposed
        valuesWithId1.add(valueWithId1Subscription.value);
      });

      final shortValuesSubscription = valueStore.query(
        where: (cols) => cols['length'].lessThan(5),
      );
      final shortValues = [shortValuesSubscription.value];
      shortValuesSubscription.addListener(() {
        // Add new values as they are exposed
        shortValues.add(shortValuesSubscription.value);
      });

      expect(
        valuesWithId1,
        [null],
      );
      expect(
        shortValues,
        [[]],
      );

      /// Add first entry
      {
        valueStore.write(_ValueWrapper(1, 'one'));

        // both subscriptions got updated
        expect(
          valuesWithId1,
          [
            null,
            isA<_ValueWrapper>().having((w) => w.value, 'value', 'one'),
          ],
        );
        expect(
          shortValues,
          [
            [],
            [isA<_ValueWrapper>().having((w) => w.value, 'value', 'one')],
          ],
        );
      }

      /// Add second entry, matching only the query
      {
        valueStore.write(_ValueWrapper(2, 'two'));

        // both subscriptions got updated
        expect(
          valuesWithId1,
          [
            null,
            isA<_ValueWrapper>().having((w) => w.value, 'value', 'one'),
          ],
        );
        expect(
          shortValues,
          [
            [],
            [isA<_ValueWrapper>().having((w) => w.value, 'value', 'one')],
            [
              isA<_ValueWrapper>().having((w) => w.value, 'value', 'one'),
              isA<_ValueWrapper>().having((w) => w.value, 'value', 'two'),
            ],
          ],
        );
      }

      /// Re-insert first entry again, which should not cause an update, as the value has not changed
      {
        valueStore.write(_ValueWrapper(1, 'one'));

        // subscriptions did not emit a new value
        expect(
          valuesWithId1,
          [
            null,
            isA<_ValueWrapper>().having((w) => w.value, 'value', 'one'),
          ],
        );
        expect(
          shortValues,
          [
            [],
            [isA<_ValueWrapper>().having((w) => w.value, 'value', 'one')],
            [
              isA<_ValueWrapper>().having((w) => w.value, 'value', 'one'),
              isA<_ValueWrapper>().having((w) => w.value, 'value', 'two'),
            ],
          ],
        );
      }

      /// Insert another entry which does not match any query, and thus should not cause an update
      {
        valueStore.write(_ValueWrapper(3, 'three'));

        // subscriptions did not emit a new value
        expect(
          valuesWithId1,
          [
            null,
            isA<_ValueWrapper>().having((w) => w.value, 'value', 'one'),
          ],
        );
        expect(
          shortValues,
          [
            [],
            [isA<_ValueWrapper>().having((w) => w.value, 'value', 'one')],
            [
              isA<_ValueWrapper>().having((w) => w.value, 'value', 'one'),
              isA<_ValueWrapper>().having((w) => w.value, 'value', 'two'),
            ],
          ],
        );
      }

      /// Insert and update to entity 1, which should cause both to update
      {
        valueStore.write(_ValueWrapper(1, 'eins'));

        // both subscriptions got updated
        expect(
          valuesWithId1,
          [
            null,
            isA<_ValueWrapper>().having((w) => w.value, 'value', 'one'),
            isA<_ValueWrapper>().having((w) => w.value, 'value', 'eins'),
          ],
        );
        expect(
          shortValues,
          [
            [],
            [isA<_ValueWrapper>().having((w) => w.value, 'value', 'one')],
            [
              isA<_ValueWrapper>().having((w) => w.value, 'value', 'one'),
              isA<_ValueWrapper>().having((w) => w.value, 'value', 'two'),
            ],
            [
              isA<_ValueWrapper>().having((w) => w.value, 'value', 'eins'),
              isA<_ValueWrapper>().having((w) => w.value, 'value', 'two'),
            ],
          ],
        );
      }

      valueWithId1Subscription.dispose();
      shortValuesSubscription.dispose();

      expect(valueStore.subscriptionCount, 0);
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

      expect(store.queryOnce(), isEmpty);

      store.write(
        _AllSupportedIndexTypes.defaultIfNull(string: 'default'),
      );
      store.write(
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

      expect(store.queryOnce(), hasLength(2));

      // Valid queries with values
      expect(
        store.queryOnce(where: (cols) => cols['string'].equals('all_set')),
        hasLength(1),
      );
      expect(
        store.queryOnce(where: (cols) => cols['stringOpt'].equals('string_2')),
        hasLength(1),
      );
      expect(
        store.queryOnce(where: (cols) => cols['number'].equals(1)),
        hasLength(1),
      );
      expect(
        store.queryOnce(where: (cols) => cols['numberOpt'].equals(2)),
        hasLength(1),
      );
      expect(
        store.queryOnce(where: (cols) => cols['integer'].equals(3)),
        hasLength(1),
      );
      expect(
        store.queryOnce(where: (cols) => cols['integerOpt'].equals(4)),
        hasLength(1),
      );
      expect(
        store.queryOnce(where: (cols) => cols['stringOpt'].equals('string_2')),
        hasLength(1),
      );
      expect(
        store.queryOnce(where: (cols) => cols['float'].equals(5.678)),
        hasLength(1),
      );
      expect(
        store.queryOnce(where: (cols) => cols['floatOpt'].equals(6.789)),
        hasLength(1),
      );
      expect(
        store.queryOnce(where: (cols) => cols['boolean'].equals(false)),
        hasLength(2), //  as this also finds the default one
      );
      expect(
        store.queryOnce(where: (cols) => cols['booleanOpt'].equals(true)),
        hasLength(1),
      );
      expect(
        store.queryOnce(
          where: (cols) => cols['dateTime'].equals(DateTime.utc(2000)),
        ),
        hasLength(1),
      );
      expect(
        store.queryOnce(
          where: (cols) => cols['dateTimeOpt'].equals(DateTime.utc(2100)),
        ),
        hasLength(1),
      );

      // Valid queries with `null`
      expect(
        store.queryOnce(where: (cols) => cols['stringOpt'].equals(null)),
        hasLength(1),
      );
      expect(
        store.queryOnce(where: (cols) => cols['numberOpt'].equals(null)),
        hasLength(1),
      );
      expect(
        store.queryOnce(where: (cols) => cols['integerOpt'].equals(null)),
        hasLength(1),
      );
      expect(
        store.queryOnce(where: (cols) => cols['stringOpt'].equals(null)),
        hasLength(1),
      );
      expect(
        store.queryOnce(where: (cols) => cols['floatOpt'].equals(null)),
        hasLength(1),
      );
      expect(
        store.queryOnce(where: (cols) => cols['booleanOpt'].equals(null)),
        hasLength(1),
      );
      expect(
        store.queryOnce(where: (cols) => cols['dateTimeOpt'].equals(null)),
        hasLength(1),
      );

      // type mismatches
      expect(
        () => store.queryOnce(where: (cols) => cols['string'].equals(null)),
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
        () => store.queryOnce(where: (cols) => cols['boolean'].equals(1.0)),
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
        () => store.queryOnce(where: (cols) => cols['dateTime'].equals('')),
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

  test(
    'Foreign key constraint persists across sessions',
    () async {
      final path =
          '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

      final db = IndexedEntityDabase.open(path);

      final indexedEntityConnector =
          IndexedEntityConnector<_AllSupportedIndexTypes, String, String>(
        entityKey: 'indexed_entity',
        getPrimaryKey: (e) => e.string,
        getIndices: (index) {
          index((e) => e.string, as: 'string');
        },
        serialize: (f) => jsonEncode(f.toJSON()),
        deserialize: (s) => _AllSupportedIndexTypes.fromJSON(
          jsonDecode(s) as Map<String, dynamic>,
        ),
      );

      final store = db.entityStore(indexedEntityConnector);

      expect(store.queryOnce(), isEmpty);

      final e = _AllSupportedIndexTypes.defaultIfNull(string: 'default');

      store.write(e);

      db.dispose();

      // now open again, ensuring foreign keys are still on and thus `index`
      // will be cleaned up with entity removals & overwrites

      // delete & insert
      {
        final db = IndexedEntityDabase.open(path);

        final store = db.entityStore(indexedEntityConnector);

        store.delete(key: 'default');
        expect(store.queryOnce(), isEmpty);
        store.write(e);

        db.dispose();
      }

      // second insert (overwrite)
      {
        final db = IndexedEntityDabase.open(path);

        final store = db.entityStore(indexedEntityConnector);

        store.write(e);

        db.dispose();
      }
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

    expect(store.queryOnce(), isEmpty);

    final now = DateTime.now();

    store.write(
      _AllSupportedIndexTypes.defaultIfNull(
        string: 'default',
        dateTime: now,
        float: 1000,
      ),
    );

    expect(
      store.queryOnce(where: (cols) => cols['dateTime'].equals(now)),
      hasLength(1),
    );
    expect(
      store.queryOnce(where: (cols) => cols['dateTime'].equals(now.toUtc())),
      hasLength(1),
    );

    expect(
      store.queryOnce(where: (cols) => cols['dateTimeOpt'].equals(null)),
      hasLength(1),
    );

    // DateTime: less than, greater than
    expect(
      store.queryOnce(where: (cols) => cols['dateTime'].lessThan(now)),
      isEmpty,
    );
    expect(
      store.queryOnce(where: (cols) => cols['dateTime'].lessThanOrEqual(now)),
      hasLength(1),
    );
    expect(
      store.queryOnce(where: (cols) => cols['dateTime'].greaterThan(now)),
      isEmpty,
    );
    expect(
      store.queryOnce(
        where: (cols) => cols['dateTime'].greaterThanOrEqual(now),
      ),
      hasLength(1),
    );
    expect(
      store.queryOnce(
        where: (cols) => cols['dateTime'].greaterThan(
          now.subtract(const Duration(seconds: 1)),
        ),
      ),
      hasLength(1),
    );

    // Null field: Should not be found for less than, equal, or greater than
    expect(
      store.queryOnce(where: (cols) => cols['dateTimeOpt'].equals(now)),
      isEmpty,
    );
    expect(
      store.queryOnce(where: (cols) => cols['dateTimeOpt'].lessThan(now)),
      isEmpty,
    );
    expect(
      store.queryOnce(
        where: (cols) => cols['dateTimeOpt'].lessThanOrEqual(now),
      ),
      isEmpty,
    );
    expect(
      store.queryOnce(where: (cols) => cols['dateTimeOpt'].greaterThan(now)),
      isEmpty,
    );
    expect(
      store.queryOnce(
        where: (cols) => cols['dateTimeOpt'].greaterThanOrEqual(now),
      ),
      isEmpty,
    );

    /// Numeric
    expect(
      store.queryOnce(where: (cols) => cols['float'].equals(1000)),
      hasLength(1),
    );
    expect(
      store.queryOnce(where: (cols) => cols['float'].greaterThan(1000)),
      isEmpty,
    );
    expect(
      store.queryOnce(where: (cols) => cols['float'].greaterThan(999.6)),
      hasLength(1),
    );
    expect(
      store.queryOnce(
        where: (cols) => cols['float'].greaterThanOrEqual(1000.0),
      ),
      hasLength(1),
    );

    // String contains
    expect(
      store.queryOnce(where: (cols) => cols['string'].contains('def')),
      hasLength(1),
    );
    expect(
      store.queryOnce(where: (cols) => cols['string'].contains('fau')),
      hasLength(1),
    );
    expect(
      store.queryOnce(where: (cols) => cols['string'].contains('lt')),
      hasLength(1),
    );
    expect(
      store.queryOnce(where: (cols) => cols['string'].contains('default')),
      hasLength(1),
    );
    expect(
      store.queryOnce(where: (cols) => cols['string'].contains('FAU')),
      isEmpty, // does not match, as it's case sensitive by default
    );
    expect(
      store.queryOnce(
        where: (cols) => cols['string'].contains('FAU', caseInsensitive: true),
      ),
      hasLength(1), // now matches, as we disabled case-sensitivity
    );
    expect(
      // `null`-able & unsued field
      store.queryOnce(where: (cols) => cols['stringOpt'].contains('def')),
      isEmpty,
    );
    expect(
      // `null` string field allows the query, but does not have a match yet
      store.queryOnce(where: (cols) => cols['stringOpt'].contains('def')),
      isEmpty,
    );
    store.write(
      _AllSupportedIndexTypes.defaultIfNull(stringOpt: 'xxxx'),
    );
    expect(
      // `null` string field with value has a match now
      store.queryOnce(where: (cols) => cols['stringOpt'].contains('x')),
      hasLength(1),
    );
  });

  test('Limit', () async {
    final path = '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

    final db = IndexedEntityDabase.open(path);

    final indexedEntityConnector = IndexedEntityConnector<int, String, String>(
      entityKey: 'indexed_entity',
      getPrimaryKey: (i) => '$i',
      getIndices: (index) {
        index((e) => e, as: 'value');
      },
      serialize: (i) => i.toString(),
      deserialize: (s) => int.parse(s),
    );

    final store = db.entityStore(indexedEntityConnector);

    expect(store.queryOnce(), isEmpty);

    for (var i = 0; i < 10; i++) {
      store.write(i);
    }

    expect(store.queryOnce(), hasLength(10));
    expect(
      store.queryOnce(where: (cols) => cols['value'].greaterThan(-1)),
      hasLength(10),
    );
    expect(
      store.queryOnce(where: (cols) => cols['value'].greaterThan(-1), limit: 0),
      isEmpty,
    );
    expect(
      store.queryOnce(where: (cols) => cols['value'].greaterThan(-1), limit: 1),
      hasLength(1),
    );
    expect(
      store.queryOnce(where: (cols) => cols['value'].greaterThan(-1), limit: 5),
      hasLength(5),
    );
    expect(
      store.queryOnce(where: (cols) => cols['value'].greaterThan(5), limit: 5),
      equals({6, 7, 8, 9}),
    );
  });

  test('Order by', () async {
    final path = '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

    final db = IndexedEntityDabase.open(path);

    final random = Random();
    final randomNumbers = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]..shuffle();
    final numbersWithPrimaryKey = {
      for (final n in randomNumbers) n: random.nextInt(100000),
    };
    // debugPrint('numbersWithPrimaryKey: $numbersWithPrimaryKey');

    final indexedEntityConnector = IndexedEntityConnector<int, String, String>(
      entityKey: 'indexed_entity',
      getPrimaryKey: (i) => numbersWithPrimaryKey[i]!.toString(),
      getIndices: (index) {
        index((e) => e, as: 'value');
        index((e) => e.name, as: 'name');
        index((e) => e.isEven, as: 'isEven');
      },
      serialize: (i) => i.toString(),
      deserialize: (s) => int.parse(s),
    );

    final store = db.entityStore(indexedEntityConnector);

    expect(store.queryOnce(), isEmpty);

    for (final n in randomNumbers) {
      store.write(n);
    }

    expect(store.queryOnce(), hasLength(10));

    expect(
      store.queryOnce(
        where: (cols) => cols['value'].greaterThan(-1),
        orderBy: ('value', SortOrder.asc),
      ),
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    );
    expect(
      store.queryOnce(
        where: (cols) => cols['value'].greaterThan(-1),
        orderBy: ('value', SortOrder.desc),
      ),
      [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
    );

    expect(
      store.queryOnce(
        where: (cols) => cols['value'].greaterThan(-1),
        orderBy: ('value', SortOrder.asc),
        limit: 3,
      ),
      [0, 1, 2],
    );
    expect(
      store.queryOnce(
        where: (cols) => cols['value'].greaterThan(-1),
        orderBy: ('value', SortOrder.desc),
        limit: 3,
      ),
      [9, 8, 7],
    );

    expect(
      store.queryOnce(
        where: (cols) => cols['value'].greaterThan(-1),
        orderBy: ('name', SortOrder.asc),
        limit: 3,
      ),
      [
        8, // eight
        5, // five
        4, // four
      ],
    );
    expect(
      store.queryOnce(
        where: (cols) => cols['value'].greaterThan(-1),
        orderBy: ('name', SortOrder.desc),
        limit: 3,
      ),
      equals([
        0, // zero
        2, // two
        3, // three
      ]),
    );
    expect(
      store.queryOnce(
        where: (cols) => cols['isEven'].equals(true),
        orderBy: ('name', SortOrder.desc),
        limit: 3,
      ),
      equals({
        0, // zero
        2, // two
        6, // six
      }),
    );
    expect(
      store.queryOnce(
        where: (cols) => cols['isEven'].equals(true),
        orderBy: ('name', SortOrder.asc),
        limit: 3,
      ),
      equals({
        8, // eight
        4, // four
        6, // six
      }),
    );

    expect(
      store.queryOnce(
        orderBy: ('value', SortOrder.asc),
      ),
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    );
    expect(
      store.queryOnce(
        orderBy: ('value', SortOrder.desc),
      ),
      [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
    );
  });

  test('single', () {
    final path = '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

    final db = IndexedEntityDabase.open(path);

    final indexedEntityConnector = IndexedEntityConnector<int, String, String>(
      entityKey: 'indexed_entity',
      getPrimaryKey: (i) => '$i',
      getIndices: (index) {
        index((e) => e, as: 'value');
        index((e) => e.isEven, as: 'isEven');
      },
      serialize: (i) => i.toString(),
      deserialize: (s) => int.parse(s),
    );

    final store = db.entityStore(indexedEntityConnector);

    expect(store.queryOnce(), isEmpty);

    for (final n in [1, 2, 3]) {
      store.write(n);
    }

    expect(
      store.singleOnce(where: (cols) => cols['value'].equals(10)),
      isNull,
    );
    expect(
      store.singleOnce(where: (cols) => cols['value'].equals(3)),
      3,
    );
    expect(
      store.singleOnce(where: (cols) => cols['isEven'].equals(true)),
      2,
    );
    expect(
      // query with 2 matches
      () => store.singleOnce(where: (cols) => cols['isEven'].equals(false)),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('found at least 2 matching'),
        ),
      ),
    );
  });

  test('Delete all', () async {
    final path = '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

    final db = IndexedEntityDabase.open(path);

    final fooStore = db.entityStore(fooConnector);

    expect(fooStore.queryOnce(), isEmpty);

    fooStore.write(
      _FooEntity(id: 1, valueA: 'a', valueB: 1, valueC: true),
    );
    fooStore.write(
      _FooEntity(id: 2, valueA: 'b', valueB: 2, valueC: true),
    );

    expect(fooStore.queryOnce(), hasLength(2));

    final singleSubscription = fooStore.read(1);
    final listSubscription =
        fooStore.query(where: (cols) => cols['b'].lessThan(5));
    expect(singleSubscription.value, isA<_FooEntity>());
    expect(listSubscription.value, hasLength(2));

    // Delete all rows
    fooStore.delete(all: true);

    expect(singleSubscription.value, isNull);
    expect(listSubscription.value, isEmpty);
    expect(fooStore.queryOnce(), isEmpty);
  });

  test(
    'delete(where: )',
    () async {
      final path =
          '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

      final db = IndexedEntityDabase.open(path);

      final valueWrappingConnector =
          IndexedEntityConnector<_ValueWrapper, int, String>(
        entityKey: 'value_wrapper',
        getPrimaryKey: (f) => f.key,
        getIndices: (index) {
          index((e) => e.value, as: 'value');
        },
        serialize: (f) => jsonEncode(f.toJSON()),
        deserialize: (s) => _ValueWrapper.fromJSON(
          jsonDecode(s) as Map<String, dynamic>,
        ),
      );

      final valueStore = db.entityStore(valueWrappingConnector);

      valueStore.writeMany([
        for (var i = 0; i < 10; i++)
          _ValueWrapper(FlutterTimeline.now + i, '$i'),
      ]);

      final allEntities = valueStore.query();
      final entityValue2 = valueStore.single(
        where: (cols) => cols['value'].equals('2'),
      );

      expect(allEntities.value, hasLength(10));
      expect(entityValue2.value, isNotNull);

      // no match
      valueStore.delete(where: (cols) => cols['value'].equals('11'));
      expect(allEntities.value, hasLength(10));
      expect(entityValue2.value, isNotNull);

      // no match for complete query
      valueStore.delete(
        where: (cols) => cols['value'].equals('11') & cols['value'].equals('2'),
      );
      expect(allEntities.value, hasLength(10));
      expect(entityValue2.value, isNotNull);

      // match delete 2 entries
      valueStore.delete(
        where: (cols) => cols['value'].equals('2') | cols['value'].equals('7'),
      );
      expect(allEntities.value, hasLength(8));
      expect(entityValue2.value, isNull);

      allEntities.dispose();
      entityValue2.dispose();

      expect(valueStore.subscriptionCount, 0);
    },
  );

  test(
    'writeMany',
    () {
      final path =
          '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

      final db = IndexedEntityDabase.open(path);

      final valueWrappingConnector =
          IndexedEntityConnector<_IntValueWrapper, int, String>(
        entityKey: 'value_wrapper',
        getPrimaryKey: (f) => f.key,
        getIndices: (index) {
          index((e) => e.value % 2 == 0, as: 'even');
          index((e) => e.batch, as: 'batch');
        },
        serialize: (f) => jsonEncode(f.toJSON()),
        deserialize: (s) => _IntValueWrapper.fromJSON(
          jsonDecode(s) as Map<String, dynamic>,
        ),
      );

      final store = db.entityStore(valueWrappingConnector);

      final allEntities = store.query();
      final evenEntities = store.query(
        where: (cols) => cols['even'].equals(true),
      );
      final batch1Entities = store.query(
        where: (cols) => cols['batch'].equals(1),
      );
      final batch2Entities = store.query(
        where: (cols) => cols['batch'].equals(2),
      );

      // writeMany
      {
        final entities = [
          for (var i = 0; i < 1000; i++) _IntValueWrapper(i, i, 1),
        ];

        store.writeMany(entities);
      }

      expect(allEntities.value, hasLength(1000));
      expect(evenEntities.value, hasLength(500));
      expect(batch1Entities.value, hasLength(1000));
      expect(batch2Entities.value, isEmpty);

      // writeMany again (in-place updates, index update with new batch ID)
      {
        final entities = [
          for (var i = 0; i < 1000; i++) _IntValueWrapper(i, i, 2),
        ];

        store.writeMany(entities);
      }

      expect(allEntities.value, hasLength(1000));
      expect(evenEntities.value, hasLength(500));
      expect(evenEntities.value.first.batch, 2); // value got updated
      expect(batch1Entities.value, isEmpty);
      expect(batch2Entities.value, hasLength(1000));

      allEntities.dispose();
      evenEntities.dispose();
      batch1Entities.dispose();
      batch2Entities.dispose();

      db.dispose();
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

final fooConnectorWithIndexOnBAndC =
    IndexedEntityConnector<_FooEntity, int, String>(
  entityKey: fooConnector.entityKey,
  getPrimaryKey: fooConnector.getPrimaryKey,
  getIndices: (index) {
    index((e) => e.valueB + 1000, as: 'b'); // updated index B
    index((e) => e.valueC, as: 'c');
  },
  serialize: fooConnector.serialize,
  deserialize: fooConnector.deserialize,
);

final fooConnectorWithUniqueIndexOnBAndIndexOnC =
    IndexedEntityConnector<_FooEntity, int, String>(
  entityKey: fooConnector.entityKey,
  getPrimaryKey: fooConnector.getPrimaryKey,
  getIndices: (index) {
    index((e) => e.valueB + 1000, as: 'b', unique: true); // updated index B
    index((e) => e.valueC, as: 'c');
  },
  serialize: fooConnector.serialize,
  deserialize: fooConnector.deserialize,
);

class _AllSupportedIndexTypes {
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

extension on int {
  String get name {
    switch (this) {
      case 0:
        return 'zero';
      case 1:
        return 'one';
      case 2:
        return 'two';
      case 3:
        return 'three';
      case 4:
        return 'four';
      case 5:
        return 'five';
      case 6:
        return 'six';
      case 7:
        return 'seven';
      case 8:
        return 'eight';
      case 9:
        return 'nine';

      default:
        throw '$this not mapped to a name';
    }
  }
}

/// A value wrapper class which only has object identity, and no value-based `==` implementation.
///
/// This way we can test that change updates are already prevented on the store-layer and do not depend on the `ValueNotifier` preventing updates (due to the current and new value being equal).
class _ValueWrapper {
  _ValueWrapper(
    this.key,
    this.value,
  );

  final int key;
  final String value;

  Map<String, dynamic> toJSON() {
    return {
      'key': key,
      'value': value,
    };
  }

  static _ValueWrapper fromJSON(Map<String, dynamic> json) {
    return _ValueWrapper(
      json['key'],
      json['value'],
    );
  }

  @override
  String toString() {
    return '_ValueWrapper($key, $value)';
  }
}

class _IntValueWrapper {
  _IntValueWrapper(
    this.key,
    this.value,
    this.batch,
  );

  final int key;
  final int value;
  final int batch;

  Map<String, dynamic> toJSON() {
    return {
      'key': key,
      'value': value,
      'batch': batch,
    };
  }

  static _IntValueWrapper fromJSON(Map<String, dynamic> json) {
    return _IntValueWrapper(
      json['key'],
      json['value'],
      json['batch'],
    );
  }

  @override
  String toString() {
    return '_IntValueWrapper($key, $value, $batch)';
  }
}
