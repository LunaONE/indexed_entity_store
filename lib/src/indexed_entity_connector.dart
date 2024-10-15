import 'package:indexed_entity_store/indexed_entity_store.dart';

abstract class IndexedEntityConnector<T /* entity */, K /* primary key */,
    S /* storage format */ > {
  factory IndexedEntityConnector({
    required String entityKey,
    required K Function(T) getPrimaryKey,
    required void Function(IndexCollector<T> index) getIndices,
    required S Function(T) serialize,
    required T Function(S) deserialize,
  }) {
    return _IndexedEntityConnector(
      entityKey,
      getPrimaryKey,
      getIndices,
      serialize,
      deserialize,
    );
  }

  String get entityKey;

  K getPrimaryKey(T e);

  void getIndices(IndexCollector<T> index);

  /// String or bytes
  S serialize(T e);

  T deserialize(S s);
}

class _IndexedEntityConnector<T, K, S>
    implements IndexedEntityConnector<T, K, S> {
  _IndexedEntityConnector(
    this.entityKey,
    this._getPrimaryKey,
    this._getIndices,
    this._serialize,
    this._deserialize,
  );

  @override
  final String entityKey;

  final K Function(T) _getPrimaryKey;

  final void Function(IndexCollector<T> index) _getIndices;

  final S Function(T) _serialize;

  final T Function(S) _deserialize;

  @override
  K getPrimaryKey(T e) => _getPrimaryKey(e);

  @override
  S serialize(T e) => _serialize(e);

  @override
  T deserialize(S s) => _deserialize(s);

  @override
  void getIndices(IndexCollector<T> index) => _getIndices(index);
}
