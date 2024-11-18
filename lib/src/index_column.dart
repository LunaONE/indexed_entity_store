part of 'index_entity_store.dart';

/// An indexed column of an [IndexedEntityStore]
///
/// This provides an interface to indexed fields, which are the only queries that can be executed on a store
/// (so that we never end up in a full table scan to look for a result).
class IndexColumn<T /* entity type */, I /* index type */ > {
  IndexColumn._({
    required String entity,
    required String field,
    required I Function(T e) getIndexValue,
    required String? referencedEntity,
    required bool unique,
  })  : _entity = entity,
        _field = field,
        _getIndexValueFunc = getIndexValue,
        _referencedEntity = referencedEntity,
        _unique = unique {
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

    if (referencedEntity != null &&
        (_typeEqual<I, String?>() ||
            _typeEqual<I, num?>() ||
            _typeEqual<I, int?>() ||
            _typeEqual<I, double?>() ||
            _typeEqual<I, bool?>() ||
            _typeEqual<I, DateTime?>())) {
      throw Exception(
        'Can not create index for field "$field" referencing "$referencedEntity" where the "value" is nullable. Type is $I.',
      );
    }
  }

  final String _entity;

  final String _field;

  final I Function(T e) _getIndexValueFunc;

  final String? _referencedEntity;

  final bool _unique;

  // Usually I, just for `DateTime` we have some special handling to support that out of the box (by converting to int)
  dynamic _getIndexValue(T e) {
    final v = _getIndexValueFunc(e);
    if (v is DateTime) {
      return v.microsecondsSinceEpoch;
    }

    return v;
  }

  /// Returns a query matching index values which are equal to [value]
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

  /// Returns a query matching index values which are greater than [value]
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

  /// Returns a query matching index values which are greater than or equal to [value]
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

  /// Returns a query matching index values which are less than [value]
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

  /// Returns a query matching index values which are less than or equal to [value]
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

  /// Returns a query matching index values which contain [value]
  ///
  /// By default this uses a case-sensitive string comparison, but can be changed to be case-insensitive via [caseInsensitive].
  Query contains(dynamic value, {bool caseInsensitive = false}) {
    if (value is! String || value is! I) {
      throw Exception(
        'Can not build query as field "$_field" needs a value of type $String, but got ${value.runtimeType}.',
      );
    }

    return _ContainsStringQuery(
      _entity,
      _field,
      value,
      caseInsensitive: caseInsensitive,
    );
  }
}

bool _typeEqual<T, Y>() => T == Y;
