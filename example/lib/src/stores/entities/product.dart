class Product {
  final int id;
  final String name;

  Product({
    required this.id,
    required this.name,
  });

  // These would very likely be created by [json_serializable](https://pub.dev/packages/json_serializable)
  // or [freezed](https://pub.dev/packages/freezed) already for your models
  Map<String, dynamic> toJSON() {
    return {
      'id': id,
      'name': name,
    };
  }

  static Product fromJSON(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      name: json['name'],
    );
  }
}

class ProductDetail {
  final int id;
  final String name;
  final String brand;
  final String description;
  final double price;
  final DateTime fetchedAt;

  ProductDetail({
    required this.id,
    required this.name,
    required this.brand,
    required this.description,
    required this.price,
    required this.fetchedAt,
  });

  // These would very likely be created by [json_serializable](https://pub.dev/packages/json_serializable)
  // or [freezed](https://pub.dev/packages/freezed) already for your models
  Map<String, dynamic> toJSON() {
    return {
      'id': id,
      'name': name,
      'brand': brand,
      'description': description,
      'price': price,
      'fetchedAt': fetchedAt.millisecondsSinceEpoch,
    };
  }

  static ProductDetail fromJSON(Map<String, dynamic> json) {
    return ProductDetail(
      id: json['id'],
      name: json['name'],
      brand: json['brand'],
      description: json['description'],
      price: json['price'],
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(json['fetchedAt']),
    );
  }
}
