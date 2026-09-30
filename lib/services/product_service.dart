import 'package:cloud_firestore/cloud_firestore.dart';

/// Where a product's count sits against the store's low-stock threshold — the
/// design's traffic-light status.
enum StockStatus { inStock, lowStock, outOfStock }

/// One product in a tindahan's catalog, from `stores/{storeId}/products/{id}`
/// or the on-device copy in [ProductRepository].
///
/// Money is whole centavos, as in the cart: doubles drift. Optional fields are
/// null rather than empty so the UI can show "—" without second-guessing.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.stock,
    required this.sellCentavos,
    this.buyCentavos,
    this.size,
    this.sku,
    this.categories = const [],
    this.imageUrl,
    this.stockAlerts = true,
  });

  /// Reads a product defensively, from Firestore or local JSON alike: both
  /// hand back `dynamic`, and one malformed field should not take the whole
  /// list down.
  ///
  /// Products saved before multiple categories carry a single `category`
  /// string; it is read as a one-item [categories].
  factory Product.fromMap(String id, Map<String, dynamic> data) {
    String? text(String key) {
      final value = data[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    int? whole(String key) {
      final value = data[key];
      return value is num ? value.round() : null;
    }

    final rawCategories = data['categories'];
    final legacyCategory = text('category');
    final categories = rawCategories is List
        ? [
            for (final c in rawCategories)
              if (c is String && c.trim().isNotEmpty) c.trim(),
          ]
        : [?legacyCategory];

    return Product(
      id: id,
      name: text('name') ?? 'Unnamed product',
      stock: whole('stock') ?? 0,
      sellCentavos: whole('sellCentavos') ?? 0,
      buyCentavos: whole('buyCentavos'),
      size: text('size'),
      sku: text('sku'),
      categories: List.unmodifiable(categories),
      imageUrl: text('imageUrl'),
      // Missing on products saved before the setting existed: on.
      stockAlerts: data['stockAlerts'] is bool
          ? data['stockAlerts'] as bool
          : true,
    );
  }

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Product.fromMap(doc.id, doc.data() ?? const {});

  final String id;
  final String name;

  /// Can go negative: the store allows a sale to oversell rather than block
  /// it, since stock changes are offline increments.
  final int stock;
  final int sellCentavos;
  final int? buyCentavos;

  /// Free text such as `330ml`, `40g` or `Large`; null when the product has
  /// no size.
  final String? size;
  final String? sku;

  /// Every category the product is filed under, main one first. Empty when
  /// uncategorized.
  final List<String> categories;
  final String? imageUrl;

  /// Whether the product can be flagged LOW STOCK and counted in the
  /// Inventory alerts. Off for items the store keeps but rarely sells, so
  /// they don't bury the ones that matter.
  final bool stockAlerts;

  /// The main category: the one the SKU is built from.
  String? get mainCategory => categories.isEmpty ? null : categories.first;

  /// The name with its size, for the cart and anywhere else one line has to
  /// tell sizes apart: `Piattos Cheese · 40g`.
  String get displayName => size == null ? name : '$name · $size';

  /// Every field but [id], which is the document or storage key.
  Map<String, dynamic> toMap() => {
    'name': name,
    'stock': stock,
    'sellCentavos': sellCentavos,
    'buyCentavos': buyCentavos,
    'size': size,
    'sku': sku,
    'categories': categories,
    'imageUrl': imageUrl,
    'stockAlerts': stockAlerts,
  };

  /// Sell minus buy price, or null when the buy price is unknown.
  int? get marginCentavos =>
      buyCentavos == null ? null : sellCentavos - buyCentavos!;

  /// Out of stock is a fact about the shelf and always shows; low stock is a
  /// warning, so only products with [stockAlerts] on get it.
  StockStatus statusFor(int lowStockThreshold) {
    if (stock <= 0) return StockStatus.outOfStock;
    if (stockAlerts && stock <= lowStockThreshold) return StockStatus.lowStock;
    return StockStatus.inStock;
  }

  /// Whether this product counts toward the Inventory alerts.
  bool needsAlert(int lowStockThreshold) =>
      stockAlerts && statusFor(lowStockThreshold) != StockStatus.inStock;
}

/// What the "Add New Product" form collects before anything is written.
/// Optional fields are null or empty, as on [Product].
class ProductDraft {
  const ProductDraft({
    required this.name,
    required this.sellCentavos,
    this.buyCentavos,
    this.stock = 0,
    this.size,
    this.sku,
    this.categories = const [],
    this.stockAlerts = true,
  });

  final String name;
  final int sellCentavos;
  final int? buyCentavos;
  final int stock;
  final String? size;
  final String? sku;

  /// Main category first.
  final List<String> categories;
  final bool stockAlerts;

  Product toProduct(String id) => Product(
    id: id,
    name: name,
    stock: stock,
    sellCentavos: sellCentavos,
    buyCentavos: buyCentavos,
    size: size,
    sku: sku,
    categories: List.unmodifiable(categories),
    stockAlerts: stockAlerts,
  );
}

/// The server side of a store's catalog, as [ProductRepository] sees it.
/// An interface so tests, and the offline sync to come, can stand in for
/// Firestore.
abstract interface class ProductRemote {
  /// A fresh id for a product that may not reach the server for a while.
  String newId();

  /// The whole catalog, once. Throws if the server can't be reached.
  Future<List<Product>> fetchAll();

  /// Creates or overwrites [product]. Throws if the server refuses it.
  Future<void> save(Product product);
}

/// [ProductRemote] backed by `stores/{storeId}/products` in Firestore.
class ProductService implements ProductRemote {
  ProductService(this.storeId);

  static const productsCollection = 'products';

  final String storeId;

  CollectionReference<Map<String, dynamic>> get _products => FirebaseFirestore
      .instance
      .collection('stores')
      .doc(storeId)
      .collection(productsCollection);

  /// Generated on the device, so it works with no connection.
  @override
  String newId() => _products.doc().id;

  /// Asks the server rather than Firestore's own cache: the on-device copy
  /// is [ProductRepository]'s job, and a stale cache answer would overwrite
  /// it with an older list.
  @override
  Future<List<Product>> fetchAll() async {
    final snapshot = await _products.get(
      const GetOptions(source: Source.server),
    );
    return snapshot.docs.map(Product.fromDoc).toList();
  }

  /// The opening stock is written as a plain value: the document is new, so
  /// there is no concurrent count to lose. Later changes must be increments.
  @override
  Future<void> save(Product product) {
    return _products.doc(product.id).set({
      ...product.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
