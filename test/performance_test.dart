import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  test(
    'Performance',
    () async {
      final path =
          '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

      final db = IndexedEntityDabase.open(path);

      final fooStore = db.entityStore(fooConnector);

      expect(fooStore.queryOnce(), isEmpty);

      // Insert one row, so statements are prepared
      fooStore.write(
        _FooEntity(id: 0, valueA: 'a', valueB: 1, valueC: true),
      );

      const batchSize = 1000;

      // many
      {
        final sw2 = Stopwatch()..start();

        for (var i = 1; i <= batchSize; i++) {
          fooStore.write(
            _FooEntity(id: i, valueA: 'a', valueB: 1, valueC: true),
          );
        }

        debugPrint(
          '$batchSize x `write` took ${(sw2.elapsedMicroseconds / 1000).toStringAsFixed(2)}ms',
        );
      }

      // writeMany
      {
        final sw2 = Stopwatch()..start();

        fooStore.writeMany(
          [
            for (var i = batchSize + 1; i <= batchSize * 2; i++)
              _FooEntity(id: i, valueA: 'a', valueB: 1, valueC: true),
          ],
        );

        debugPrint(
          '`writeMany` took ${(sw2.elapsedMicroseconds / 1000).toStringAsFixed(2)}ms',
        );
      }

      // writeMany again (which needs to replace all existing entities and update the indices)
      {
        final sw2 = Stopwatch()..start();

        fooStore.writeMany(
          [
            for (var i = batchSize + 1; i <= batchSize * 2; i++)
              _FooEntity(id: i, valueA: 'aaaaaa', valueB: 111111, valueC: true),
          ],
        );

        debugPrint(
          '`writeMany` again took ${(sw2.elapsedMicroseconds / 1000).toStringAsFixed(2)}ms',
        );
      }

      expect(fooStore.queryOnce(), hasLength(batchSize * 2 + 1));
      expect(
        fooStore.queryOnce(where: (cols) => cols['b'].greaterThan(0)),
        hasLength(batchSize * 2 + 1),
      );
    },
    skip: !Platform.isMacOS, // only run locally for now
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
