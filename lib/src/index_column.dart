part of 'index_entity_store.dart';

class IndexColumn<T /* entity type */, I /* index type */ > {
  IndexColumn({
    required String entity,
    required String field,
    required I Function(T e) getIndexValue,
  })  : _entity = entity,
        _field = field,
        _getIndexValueFunc = getIndexValue {
    if (!_typeEqual<I, String>() &&
        !_typeEqual<I, String?>() &&
        !_typeEqual<I, num>() &&
        !_typeEqual<I, num?>() &&
        !_typeEqual<I, int>() &&
        !_typeEqual<I, int?>() &&
        !_typeEqual<I, double>() &&
        !_typeEqual<I, double?>() &&
        !_typeEqual<I, bool>() &&
        !_typeEqual<I, bool?>() &&
        !_typeEqual<I, DateTime>() &&
        !_typeEqual<I, DateTime?>()) {
      throw Exception(
        'Can not create index for field "$field", as type can not be asserted. Type is $I.',
      );
    }
  }

  final String _entity;

  final String _field;

  final I Function(T e) _getIndexValueFunc;

  // Usually I, just for `DateTime` we have some special handling to support that out of the box (by converting to String)
  dynamic _getIndexValue(T e) {
    final v = _getIndexValueFunc(e);
    if (v is DateTime) {
      return v.toIso8601String();
    }

    return v;
  }

  Query equals(dynamic value) {
    if (value is! I) {
      throw Exception(
        'Can not build query as field "$_field" needs a value of type $I, but got ${value.runtimeType}.',
      );
    }

    return _EqualQuery(
      _entity,
      _field,
      value is DateTime ? value.toIso8601String() : value,
    );
  }
}

bool _typeEqual<T, Y>() => T == Y;
