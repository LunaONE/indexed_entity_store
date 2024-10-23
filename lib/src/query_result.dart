part of 'index_entity_store.dart';

typedef MappedDBResult<T> = ({List<dynamic> dbValues, T result});

class QueryResult<T> implements ValueListenable<T> {
  QueryResult._({
    required MappedDBResult<T> initialValue,
    void Function(QueryResult<T> self)? onDispose,
  })  : _value = ValueNotifier(initialValue),
        _onDispose = onDispose;

  final ValueNotifier<MappedDBResult<T>> _value;

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
  T get value => _value.value.result;

  @mustCallSuper
  void dispose() {
    _value.dispose();

    _onDispose?.call(this);
  }
}
