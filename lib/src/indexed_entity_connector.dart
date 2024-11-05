import 'package:indexed_entity_store/indexed_entity_store.dart';

abstract class IndexedEntityConnector<T /* entity */, K /* primary key */,
    S /* storage format, string or bytes */ > {
  String get entityKey;

  K getPrimaryKey(T e);

  void getIndices(IndexCollector<T> index);

  S serialize(T e);

  T deserialize(S s);
}
