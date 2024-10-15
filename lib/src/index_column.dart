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

  // Usually I, just for `DateTime` we have some special handling to support that out of the box (by converting to int)
  dynamic _getIndexValue(T e) {
    final v = _getIndexValueFunc(e);
    if (v is DateTime) {
      return v.microsecondsSinceEpoch;
    }

    return v;
  }

  // NOTE(tp): Parameters here are typed as `dynamic`, even though they must be `I`. This is done so we can throw a more detailed exeption instead of the default low-level `TypeError`
  Query equals(dynamic value) {
    if (value is int && I == double) {
      value = value.toDouble();
    }

    if (value is! I) {
      throw Exception(
        'Can not build query as field "$_field" needs a value of type $I, but got ${value.runtimeType}.',
      );
    }

    return _EqualQuery(
      _entity,
      _field,
      value,
    );
  }

  Query greaterThan(dynamic value) {
    if (value is int && I == double) {
      value = value.toDouble();
    }

    if (value is! I) {
      throw Exception(
        'Can not build query as field "$_field" needs a value of type $I, but got ${value.runtimeType}.',
      );
    }

    return _GreaterThanQuery(
      _entity,
      _field,
      value,
    );
  }

  // Query operator >(I value) {
  //   return greaterThan(value);
  // }

  Query greaterThanOrEqual(dynamic value) {
    if (value is int && I == double) {
      value = value.toDouble();
    }

    if (value is! I) {
      throw Exception(
        'Can not build query as field "$_field" needs a value of type $I, but got ${value.runtimeType}.',
      );
    }

    return _OrQuery(
      equals(value),
      _GreaterThanQuery(
        _entity,
        _field,
        value,
      ),
    );
  }

  // Query operator >=(I value) {
  //   return greaterThanOrEqual(value);
  // }

  Query lessThan(dynamic value) {
    if (value is int && I == double) {
      value = value.toDouble();
    }

    if (value is! I) {
      throw Exception(
        'Can not build query as field "$_field" needs a value of type $I, but got ${value.runtimeType}.',
      );
    }

    return _LessThanQuery(
      _entity,
      _field,
      value,
    );
  }

  // Query operator <(I value) {
  //   return lessThan(value);
  // }

  Query lessThanOrEqual(dynamic value) {
    if (value is int && I == double) {
      value = value.toDouble();
    }

    if (value is! I) {
      throw Exception(
        'Can not build query as field "$_field" needs a value of type $I, but got ${value.runtimeType}.',
      );
    }

    return _OrQuery(
      equals(value),
      _LessThanQuery(
        _entity,
        _field,
        value,
      ),
    );
  }

  // Query operator <=(I value) {
  //   return lessThanOrEqual(value);
  // }
}

bool _typeEqual<T, Y>() => T == Y;
