part of 'index_entity_store.dart';

sealed class _MappedDBResult<T> {
  /// Returns an error for the same generic type
  _ErrorDBResult<T> _error(Object e) {
    return _ErrorDBResult(e);
  }
}

class _SuccessDBResult<T> extends _MappedDBResult<T> {
  _SuccessDBResult({
    required this.dbValues,
    required this.result,
  });

  final List<dynamic> dbValues;
  final T result;
}

class _ErrorDBResult<T> extends _MappedDBResult<T> {
  _ErrorDBResult(this.error);

  final Object error;
}

class QueryResult<T> implements DisposableValueListenable<T> {
  QueryResult._({
    required _MappedDBResult<T> initialValue,
    void Function(QueryResult<T> self)? onDispose,
  })  : _value = ValueNotifier(initialValue),
        _onDispose = onDispose;

  final ValueNotifier<_MappedDBResult<T>> _value;

  final void Function(QueryResult<T> self)? _onDispose;

  @override
  void addListener(VoidCallback listener) {
    _value.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _value.removeListener(listener);
  }

  @override
  T get value => switch (_value.value) {
        _SuccessDBResult<T>(:final result) => result,
        _ErrorDBResult<T>(:final error) => throw error,
      };

  @override
  @mustCallSuper
  void dispose() {
    _value.dispose();

    _onDispose?.call(this);
  }
}
