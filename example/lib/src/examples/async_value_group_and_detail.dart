import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:indexed_entity_store_example/src/stores/entities/product.dart';
import 'package:indexed_entity_store_example/src/stores/product_connector.dart';
import 'package:indexed_entity_store_example/src/utils/extensions.dart';
import 'package:riverpod/riverpod.dart' show AsyncValue, AsyncValueX;
import 'package:value_listenable_extensions/value_listenable_extensions.dart';

class AsyncValueGroupDetailExample extends StatefulWidget {
  const AsyncValueGroupDetailExample({
    super.key,
  });

  @override
  State<AsyncValueGroupDetailExample> createState() =>
      _AsyncValueGroupDetailExampleState();
}

class _AsyncValueGroupDetailExampleState
    extends State<AsyncValueGroupDetailExample> {
  final repository = AsyncProductRepository(
    detailStore: getProductDetailStore(),
    productApi: ProductAPI(),
  );

  late final products = repository.getProducts('shoes');

  @override
  initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tap any product to see its details',
        ),
        Expanded(
          child: SingleChildScrollView(
            child: ValueListenableBuilder(
              valueListenable: products,
              builder: (context, products, _) {
                return products.when(
                  data: (products) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final product in products)
                          CupertinoListTile(
                            onTap: () => Navigator.push(
                              context,
                              ProductDetailPage(
                                productId: product.id,
                                repository: repository,
                              ).route,
                            ),
                            title: Text(product.name),
                          ),
                      ],
                    );
                  },
                  error: (e, s) => Text('$e'),
                  loading: () => const CupertinoActivityIndicator(),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    // In practice, whoever create the database, store, and repository would have to dispose it

    products.dispose();

    super.dispose();
  }
}

class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({
    super.key,
    required this.productId,
    required this.repository,
  });

  final int productId;

  // In practice this would come from the app's dependency management system of choice
  final AsyncProductRepository repository;

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();

  CupertinoPageRoute get route => CupertinoPageRoute(builder: (_) => this);
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  late final product = widget.repository.getProductDetail(widget.productId);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: product,
      builder: (context, product, _) {
        return CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(
            middle: Text('Product ${product.valueOrNull?.name}'),
          ),
          child: SafeArea(
            child: product.when(
              data: (product) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name),
                    Text(product.description),
                    Text(
                      'Last updated at ${product.fetchedAt.toIso8601String()}',
                    ),
                    Text(product.price.toStringAsFixed(2)),
                  ],
                );
              },
              error: (e, s) => Text('$e'),
              loading: () => const Center(child: CupertinoActivityIndicator()),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    product.dispose();

    super.dispose();
  }
}

class AsyncProductRepository {
  final ProductDetailStore _detailStore;
  final ProductAPI _productApi;

  AsyncProductRepository({
    required ProductDetailStore detailStore,
    required ProductAPI productApi,
  })  : _detailStore = detailStore,
        _productApi = productApi;

  // Even though this doesn't update "by itself" (e.g. no new product list are ever pushed), for demo purposes we still use the same interface as for the product detail,
  // because we still need to handle the 3 "async" states over time anyway (loading/no data, error, data loaded/succes).
  //
  // If in the future we'd update the product list (e.g. by passing it through the indexed entity store), we could just change the implementation here and all consumers could stay unchanged.
  DisposableValueListenable<AsyncValue<List<Product>>> getProducts(
    String category,
  ) {
    return _productApi.getProducts(category).asAsyncValue();
  }

  DisposableValueListenable<AsyncValue<ProductDetail>> getProductDetail(
    int productId,
  ) {
    final productQuery = _detailStore.read(productId);

    if (productQuery.value != null &&
        // If data is older than 30s, run the fetch below (but show the most recent value while it's loading)
        productQuery.value!.fetchedAt
            .isAfter(DateTime.now().subtract(const Duration(seconds: 10)))) {
      // Since we already have the value in the database, we can return a view into it (as we don't expect the product to be deleted (by maybe replaced) while we look at it)
      // The check above could easily be extended, eg. if the data is too old it might also trigger a load to get the updated product details as soon as they are available

      return productQuery.transform((v) => AsyncValue.data(v!));
    }

    // When we don't have the product details, this becomes trickier, as we have to handle both the initial load (which could fail)
    // and then potentially subsequent updates to the product details via the database.
    //
    // Thus this returns a view which is based on the database result or, if no entry exists in the database, the result from the loading request.
    // In the success/data loaded case the entity will only be read from the database, and just a transient loading or error state (which is not persisted in the database) will be read from the request.
    //
    // If this pattern occurs more often, we could of course abstract it away in a shared helper that would augment the database result with the request's response.

    return combineLatest2(
      productQuery,
      _productApi.getProductDetail(productId).then((product) {
        // When we receive the product successfully, we put it into the database,
        // from which point on the product query will deliver it to the outside
        _detailStore.write(product);

        return product;
      }).asAsyncValue(),
      (prod, result) => prod != null ? AsyncValue.data(prod) : result,
      // clean up the underlying query with the view of the current state
      dispose: productQuery.dispose,
    );
  }
}

/// This is an example product API simulating how products would be fetched from a remote server
///
/// The important part here is just that everything is async, with some deliberate delays to see the loading behavior in the UI
///
/// Note: In practice the API response type on this level would likely not be the entity that we persist locally, so there could be a mapping step in between.
class ProductAPI {
  Future<List<Product>> getProducts(String category) async {
    await Future.delayed(const Duration(seconds: 2));

    return [
      for (var i = 1; i <= 10; i++) Product(id: i, name: '$category #$i'),
    ];
  }

  Future<ProductDetail> getProductDetail(int productId) async {
    await Future.delayed(const Duration(seconds: 2));

    return ProductDetail(
      id: productId,
      name: 'Product $productId',
      brand: 'Manufacturer',
      description: 'Lorem ipsum…',
      price: productId * 100,
      fetchedAt: DateTime.now(),
    );
  }
}
