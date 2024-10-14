abstract class IndexedEntityConnector<T /* entity */, K /* primary key */,
    S /* storage format */ > {
  factory IndexedEntityConnector({
    required String entityKey,
    required K Function(T) getPrimaryKey,
    required Map<String, dynamic> Function(T?) getIndices,
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

  Map<String, dynamic> getIndices(T? e);

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

  final Map<String, dynamic> Function(T? e) _getIndices;

  final S Function(T) _serialize;

  final T Function(S) _deserialize;

  @override
  K getPrimaryKey(T e) => _getPrimaryKey(e);

  @override
  S serialize(T e) => _serialize(e);

  @override
  T deserialize(S s) => _deserialize(s);

  @override
  Map<String, dynamic> getIndices(T? e) => _getIndices(e);
}
