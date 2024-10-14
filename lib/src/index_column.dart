part of 'index_entity_store.dart';

class IndexColumn {
  IndexColumn({
    required String entity,
    required String field,
  })  : _entity = entity,
        _field = field;

  final String _entity;

  final String _field;

  Query equals(dynamic value) {
    return _EqualQuery(_entity, _field, value);
  }
}
