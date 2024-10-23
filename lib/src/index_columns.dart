part of 'index_entity_store.dart';

/// The collection of indexed columns for a given [IndexedEntityStore]
class IndexColumns {
  IndexColumns._(
    Map<String, IndexColumn> indexColumns,
  ) : _indexColumns = Map.unmodifiable(indexColumns);

  final Map<String, IndexColumn> _indexColumns;

  IndexColumn operator [](String columnName) {
    final col = _indexColumns[columnName];

    if (col == null) {
      throw Exception('"$columnName" is not a known index column');
    }

    return col;
  }
}
