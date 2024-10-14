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
    return (
      'SELECT `entity` FROM `index` WHERE `type` = ? AND `field` = "$field" AND `value` = ?',
      [entity, value],
    );
  }
}
