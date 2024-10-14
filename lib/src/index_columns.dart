part of 'index_entity_store.dart';

class IndexColumns {
  IndexColumns(
    Map<String, IndexColumn> indexColumns,
  ) : _indexColumns = Map.unmodifiable(indexColumns);

  final Map<String, IndexColumn> _indexColumns;

  IndexColumn operator [](String columnName) {
    final col = _indexColumns[columnName];

    if (col == null) {
      throw Exception('"$col" is not a known index column');
    }

    return col;
  }
}
