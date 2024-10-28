import 'dart:convert';

import 'package:indexed_entity_store/indexed_entity_store.dart';
import 'package:indexed_entity_store_example/src/stores/database_helper.dart';
import 'package:indexed_entity_store_example/src/stores/entities/product.dart';

typedef ProductDetailStore = IndexedEntityStore<ProductDetail, int>;

final productDetailConnector = IndexedEntityConnector<ProductDetail,
    int /* key type */, String /* DB type */ >(
  entityKey: 'product',
  getPrimaryKey: (t) => t.id,
  getIndices: (index) {},
  serialize: (t) => jsonEncode(t.toJSON()),
  deserialize: (s) => ProductDetail.fromJSON(
    jsonDecode(s) as Map<String, dynamic>,
  ),
);

/// Creates a new ProductDetail store, backed by a new, temporary database
///
/// In practice a single database would likely be reused with many stores,
/// and more importantly the same instance would be used instead of a new one created
/// each time as done here for the showcase.
ProductDetailStore getProductDetailStore() {
  return getNewDatabase().entityStore(productDetailConnector);
}
