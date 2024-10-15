part of 'index_entity_store.dart';

typedef QueryBuilder = Query Function(IndexColumns cols);

abstract class Query {
  Query operator &(Query other) {
    return _AndQuery(this, other);
  }

  Query operator |(Query other) {
    return _OrQuery(this, other);
  }

  (String, List<dynamic>) _entityKeysQuery();
}

class _AndQuery extends Query {
  _AndQuery(this.first, this.second);

  final Query first;
  final Query second;

  @override
  (String, List) _entityKeysQuery() {
    return (
      ' ${first._entityKeysQuery().$1} INTERSECT ${second._entityKeysQuery().$1} ',
      [...first._entityKeysQuery().$2, ...second._entityKeysQuery().$2],
    );
  }
}

class _OrQuery extends Query {
  _OrQuery(this.first, this.second);

  final Query first;
  final Query second;

  @override
  (String, List) _entityKeysQuery() {
    return (
      ' ${first._entityKeysQuery().$1} UNION ${second._entityKeysQuery().$1} ',
      [...first._entityKeysQuery().$2, ...second._entityKeysQuery().$2],
    );
  }
}

class _EqualQuery extends Query {
  _EqualQuery(this.entity, this.field, this.value);

  final String entity;
  final String field;
  final dynamic value;

  @override
  (String, List) _entityKeysQuery() {
    if (this.value == null) {
      return (
        'SELECT `entity` FROM `index` WHERE `type` = ? AND `field` = "$field" AND `value` IS NULL',
        [entity],
      );
    }

    final value = this.value is DateTime
        ? (this.value as DateTime).microsecondsSinceEpoch
        : this.value;

    return (
      'SELECT `entity` FROM `index` WHERE `type` = ? AND `field` = "$field" AND `value` = ?',
      [entity, value],
    );
  }
}

class _GreaterThanQuery extends Query {
  _GreaterThanQuery(this.entity, this.field, this.value) {
    if (value == null) {
      throw Exception(
        'Null value can not be used for "greater than" query on $entity.$field',
      );
    }
  }

  final String entity;
  final String field;
  final dynamic value;

  @override
  (String, List) _entityKeysQuery() {
    final value = this.value is DateTime
        ? (this.value as DateTime).microsecondsSinceEpoch
        : this.value;

    return (
      'SELECT `entity` FROM `index` WHERE `type` = ? AND `field` = "$field" AND `value` > ?',
      [entity, value],
    );
  }
}

class _LessThanQuery extends Query {
  _LessThanQuery(this.entity, this.field, this.value) {
    if (value == null) {
      throw Exception(
        'Null value can not be used for "less than" query on $entity.$field',
      );
    }
  }

  final String entity;
  final String field;
  final dynamic value;

  @override
  (String, List) _entityKeysQuery() {
    final value = this.value is DateTime
        ? (this.value as DateTime).microsecondsSinceEpoch
        : this.value;

    return (
      'SELECT `entity` FROM `index` WHERE `type` = ? AND `field` = "$field" AND `value` < ?',
      [entity, value],
    );
  }
}
