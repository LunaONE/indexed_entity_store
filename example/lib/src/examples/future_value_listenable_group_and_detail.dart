import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:indexed_entity_store_example/src/stores/entities/product.dart';
import 'package:indexed_entity_store_example/src/stores/product_connector.dart';
import 'package:value_listenable_extensions/value_listenable_extensions.dart';

class AsynchronousGroupDetailExample extends StatefulWidget {
  const AsynchronousGroupDetailExample({
    super.key,
  });

  @override
  State<AsynchronousGroupDetailExample> createState() =>
      _AsynchronousGroupDetailExampleState();
}

class _AsynchronousGroupDetailExampleState
    extends State<AsynchronousGroupDetailExample> {
  final repository = AsyncProductRepository(
    detailStore: getProductDetailStore(),
    productApi: ProductAPI(),
  );

  late final products = repository.getProducts('shoe');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: products,
      builder: (context, data) {
        if (!data.hasData) {
          return const Center(child: CupertinoActivityIndicator());
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tap any product to view its details',
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final product in data.requireData)
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
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    // In practice, whoever create the database, store, and repository would have to dispose it

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
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Product'),
      ),
      child: SafeArea(
        child: FutureValueSourceBuilder(
          valueSource: product,
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e) => Text('Error: $e'),
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
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Important to use the helper to cancel the "database subscription" inside the `Future`,
    // even if the `Future` may not have resolved yet, and the subscription becomes only active after
    // the widget is already disposed (at which point it will be immediately canceled then).
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

  // Since the products in a category are ephemeral and not store locally, we return just a `Future`
  // (though we could also expose a `Future<ValueSource<…>>` (which would never update) if we wanted to keep a consistent outside interface for consuming widgets)
  Future<List<Product>> getProducts(
    String category,
  ) async {
    return _productApi.getProducts(category);
  }

  /// In this example we use a `Future<ValueSource<…>>` response type so the caller can discern between loading, error, and loaded states.
  /// The first 2 are handle via the `Future`, while in the loaded state we'll only deal with the then unwrapped `ValueSource`. This could then be passed off to other
  /// widgets, which could be sure that they'll always be operating on present data (as it's non-`null` at this point).
  Future<ValueSource<ProductDetail>> getProductDetail(
    int productId,
  ) async {
    final product = _detailStore.get(productId);

    if (product.value == null) {
      try {
        final remoteEvent = await _productApi.getProductDetail(productId);

        _detailStore.insert(remoteEvent);
      } catch (e) {
        product.dispose(); // failed to load the data, close view to database

        rethrow;
      }
    }
    // optionally we could re-fetch the product here, if the local value is out of date.
    // If this is really desired it probably should not only be done as a one-off side-effect of the getter, but rather
    // happen continuously for all actively viewed products.
    else if (product.value!.fetchedAt
        .isAfter(DateTime.now().subtract(const Duration(seconds: 5)))) {
      debugPrint(
        'Local product is outdated, fetching new one in the background',
      );

      _productApi.getProductDetail(productId).then(_detailStore.insert);
    }

    // If we reached this, we now know that we have a value in the local database, and we don't expect it to ever be deleted in this case, and thus can "force unwrap" it.
    return product.transform((e) => e!);
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

class FutureValueSourceBuilder<T> extends StatelessWidget {
  const FutureValueSourceBuilder({
    super.key,
    required this.valueSource,
    required this.loading,
    required this.error,
    required this.data,
  });

  final Future<ValueSource<T>> valueSource;

  final Widget Function() loading;

  final Widget Function(Object error) error;

  final Widget Function(T value) data;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: valueSource,
      builder: (context, state) {
        if (state.hasData) {
          return ValueListenableBuilder(
            valueListenable: state.requireData,
            builder: (context, value, _) {
              return data(value);
            },
          );
        } else if (state.hasError) {
          return error(state.error!);
        } else {
          return loading();
        }
      },
    );
  }
}

// Seems like a nicer, more succinct name which still embodies the fact that the instance is "value generating"
// and thus must be cleaned up (disposed).
typedef ValueSource<T> = DisposableValueListenable<T>;

extension on Future<ValueSource> {
  void dispose() {
    then((valueSource) => valueSource.dispose());
  }
}
