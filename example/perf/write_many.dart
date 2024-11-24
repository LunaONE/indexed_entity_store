import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterTimeline, debugPrint;
import 'package:flutter/widgets.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  for (final batchSize in [10, 100, 1000, 10000]) {
    for (final singleStatement in [true, false]) {
      for (final largeValue in [true, false]) {
        debugPrint(
          '\nCase: singleStatement=$singleStatement, largeValue=$largeValue, batchSize=$batchSize',
        );

        final path = (await getApplicationCacheDirectory())
            .uri
            .resolve('./index_entity_store_test_${FlutterTimeline.now}.sqlite3')
            .toFilePath();

        debugPrint(path);

        final db = IndexedEntityDabase.open(path);

        final fooStore = db.entityStore(fooConnector);

        // Insert one row each, so statements are prepared
        fooStore.write(
          _FooEntity(id: 0, valueA: 'a', valueB: 1, valueC: true),
        );
        fooStore.writeMany(
          [_FooEntity(id: 0, valueA: 'a', valueB: 1, valueC: true)],
          singleStatement: singleStatement,
        );
        fooStore.delete(key: 0);

        // many
        {
          final sw2 = Stopwatch()..start();

          for (var i = 1; i <= batchSize; i++) {
            fooStore.write(
              _FooEntity(id: i, valueA: 'a', valueB: 1, valueC: true),
            );
          }

          final durMs = (sw2.elapsedMicroseconds / 1000).toStringAsFixed(2);
          debugPrint(
            '$batchSize x `write` took ${durMs}ms',
          );
        }

        // 10 kB
        final valueA = largeValue ? 'a1' * 1024 * 10 : 'a1';
        final valueA2 = largeValue ? 'a2' * 1024 * 10 : 'a2';

        // writeMany
        {
          final sw2 = Stopwatch()..start();

          fooStore.writeMany(
            [
              for (var i = batchSize + 1; i <= batchSize * 2; i++)
                _FooEntity(
                  id: i,
                  valueA: valueA,
                  valueB: 1,
                  valueC: true,
                ),
            ],
            singleStatement: singleStatement,
          );

          final durMs = (sw2.elapsedMicroseconds / 1000).toStringAsFixed(2);
          debugPrint(
            '`writeMany` took ${durMs}ms',
          );
        }

        // writeMany again (which needs to replace all existing entities and update the indices)
        {
          final sw2 = Stopwatch()..start();

          fooStore.writeMany(
            [
              for (var i = batchSize + 1; i <= batchSize * 2; i++)
                _FooEntity(
                  id: i,
                  valueA: valueA2,
                  valueB: 111111,
                  valueC: true,
                ),
            ],
            singleStatement: singleStatement,
          );

          final durMs = (sw2.elapsedMicroseconds / 1000).toStringAsFixed(2);
          debugPrint(
            '`writeMany` again took ${durMs}ms',
          );
        }

        if (fooStore.queryOnce().length != (batchSize * 2)) {
          throw 'unexpected store size';
        }

        db.dispose();

        File(path).deleteSync();
      }
    }
  }

  exit(0);
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
