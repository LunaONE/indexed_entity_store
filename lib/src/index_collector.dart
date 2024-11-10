part of 'index_entity_store.dart';

// NOTE(tp): This is implemented as a `class` with `call` such that we can
// correctly capture the index type `I` and forward that to `IndexColumn`
class IndexCollector<T> {
  IndexCollector._(this._entityKey);

  final String _entityKey;

  final _indices = <IndexColumn<T, dynamic>>[];

  /// Adds a new index defined by the mapping [index] and stores it in [as]
  void call<I>(
    I Function(T e) index, {
    required String as,

    /// If non-`null` this index points to the to the specified entity, like a foreign key contraints on the referenced entity's primary key
    ///
    /// When inserting an entry in this store then, the referenced entity must already exist in the database.
    /// When deleting the referenced entity, the referencing entities in this store must be removed beforehand (they will not get automatically deleted).
    /// The index is not allowed to return `null`, but rather must always return a valid primary of the referenced entity.
    String? referencing,

    /// If `true`, the value for this index (`as`) must be unique in the entire store
    bool unique = false,
  }) {
    _indices.add(
      IndexColumn<T, I>._(
        entity: _entityKey,
        field: as,
        getIndexValue: index,
        referencedEntity: referencing,
        unique: unique,
      ),
    );
  }
}
