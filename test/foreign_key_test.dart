import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indexed_entity_store/indexed_entity_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  test('Foreign key reference tests', () async {
    final path = '/tmp/index_entity_store_test_${FlutterTimeline.now}.sqlite3';

    final db = IndexedEntityDabase.open(path);

    final fooStore = db.entityStore(fooConnector);
    final fooAttachmentStore = db.entityStore(fooAttachmentConnector);

    expect(fooStore.queryOnce(), isEmpty);
    expect(fooAttachmentStore.queryOnce(), isEmpty);

    // Not valid to insert attachment where "parent" does not exist
    expect(
      () => fooAttachmentStore
          .write(_FooAttachment(id: 1, fooId: 1, value: 'adsf')),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('FOREIGN KEY constraint failed'),
        ),
      ),
    );

    final foo1 = fooStore.read(1);
    final foo1Attachments = fooAttachmentStore.query(
      where: (cols) => cols['fooId'].equals(1),
    );
    final allFooAttachments = fooAttachmentStore.query();

    fooStore.write(_FooEntity(id: 1, value: 'initial'));
    fooAttachmentStore.write(_FooAttachment(id: 1, fooId: 1, value: 'adsf'));

    expect(foo1.value?.value, 'initial');
    expect(foo1Attachments.value, hasLength(1));
    expect(allFooAttachments.value, hasLength(1));

    // Update "parent", "attachment" should be kept in place
    fooStore.write(_FooEntity(id: 1, value: 'new value'));

    expect(foo1.value?.value, 'new value');
    expect(foo1Attachments.value, hasLength(1));
    expect(allFooAttachments.value, hasLength(1));

    fooAttachmentStore.write(
      _FooAttachment(id: 2, fooId: 1, value: 'attachment 2'),
    );
    expect(foo1Attachments.value, hasLength(2));
    expect(allFooAttachments.value, hasLength(2));

    // deleting the parent is not allowed while children are still referencing it
    expect(
      () => fooStore.delete(key: 1),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('FOREIGN KEY constraint failed'),
        ),
      ),
    );

    // Add another parent, and move attachment 1 there
    fooStore.write(_FooEntity(id: 2, value: 'another foo'));
    fooAttachmentStore.write(_FooAttachment(id: 1, fooId: 2, value: 'adsf'));
    expect(foo1Attachments.value, hasLength(1));
    expect(allFooAttachments.value, hasLength(2));
    expect(
      fooAttachmentStore.queryOnce(where: (cols) => cols['fooId'].equals(2)),
      hasLength(1),
    );

    fooAttachmentStore.delete(keys: [1, 2]);
    // now that the referencing attachments are deleted, we can delete the parent as well
    fooStore.delete(keys: [1, 2]);

    expect(foo1.value, isNull);
    expect(foo1Attachments.value, isEmpty);
    expect(allFooAttachments.value, isEmpty);

    foo1.dispose();
    foo1Attachments.dispose();
    allFooAttachments.dispose();

    db.dispose();

    // TODO(tp): Test index key migrations for foreign keys (addition to non-empty stor, removal from store, name update)

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

class _FooAttachment {
  _FooAttachment({
    required this.id,
    required this.fooId,
    required this.value,
  });

  final int id;

  final int fooId;

  final String value;

  Map<String, dynamic> toJSON() {
    return {
      'id': id,
      'fooId': fooId,
      'value': value,
    };
  }

  static _FooAttachment fromJSON(Map<String, dynamic> json) {
    return _FooAttachment(
      id: json['id'],
      fooId: json['fooId'],
      value: json['value'],
    );
  }
}

final fooAttachmentConnector =
    IndexedEntityConnector<_FooAttachment, int, String>(
  entityKey: 'foo_attachment',
  getPrimaryKey: (f) => f.id,
  getIndices: (index) {
    index((e) => e.fooId, as: 'fooId', referencing: 'foo');
  },
  serialize: (f) => jsonEncode(f.toJSON()),
  deserialize: (s) => _FooAttachment.fromJSON(
    jsonDecode(s) as Map<String, dynamic>,
  ),
);
