import 'dart:convert';

import 'package:indexed_entity_store/indexed_entity_store.dart';
import 'package:indexed_entity_store_example/src/stores/database_helper.dart';
import 'package:indexed_entity_store_example/src/stores/entities/product.dart';

typedef ProductDetailStore = IndexedEntityStore<ProductDetail, int>;

class ProductDetailConnector
    implements
        IndexedEntityConnector<ProductDetail, int /* key type */,
            String /* DB type */ > {
  @override
  final entityKey = 'product';

  @override
  void getIndices(IndexCollector<ProductDetail> index) {}

  @override
  int getPrimaryKey(ProductDetail e) => e.id;

  @override
  String serialize(ProductDetail e) => jsonEncode(e.toJSON());

  @override
  ProductDetail deserialize(String s) => ProductDetail.fromJSON(
        jsonDecode(s) as Map<String, dynamic>,
      );
}

/// Creates a new ProductDetail store, backed by a new, temporary database
///
/// In practice a single database would likely be reused with many stores,
/// and more importantly the same instance would be used instead of a new one created
/// each time as done here for the showcase.
ProductDetailStore getProductDetailStore() {
  return getNewDatabase().entityStore(ProductDetailConnector());
}
