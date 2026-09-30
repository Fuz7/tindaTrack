import 'package:cloud_firestore/cloud_firestore.dart';

/// Where a product's count sits against the store's low-stock threshold — the
/// design's traffic-light status.
enum StockStatus { inStock, lowStock, outOfStock }

/// One product in a tindahan's catalog, from `stores/{storeId}/products/{id}`.
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
    this.sku,
    this.category,
    this.imageUrl,
  });

  /// Reads a product document defensively: Firestore hands back `dynamic`,
  /// and one malformed field should not take the whole list down.
  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    String? text(String key) {
      final value = data[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    int? whole(String key) {
      final value = data[key];
      return value is num ? value.round() : null;
    }

    return Product(
      id: doc.id,
      name: text('name') ?? 'Unnamed product',
      stock: whole('stock') ?? 0,
      sellCentavos: whole('sellCentavos') ?? 0,
      buyCentavos: whole('buyCentavos'),
      sku: text('sku'),
      category: text('category'),
      imageUrl: text('imageUrl'),
    );
  }

  final String id;
  final String name;

  /// Can go negative: the store allows a sale to oversell rather than block
  /// it, since stock changes are offline increments.
  final int stock;
  final int sellCentavos;
  final int? buyCentavos;
  final String? sku;
  final String? category;
  final String? imageUrl;

  /// Sell minus buy price, or null when the buy price is unknown.
  int? get marginCentavos =>
      buyCentavos == null ? null : sellCentavos - buyCentavos!;

  StockStatus statusFor(int lowStockThreshold) {
    if (stock <= 0) return StockStatus.outOfStock;
    if (stock <= lowStockThreshold) return StockStatus.lowStock;
    return StockStatus.inStock;
  }
}

/// Reads a store's product catalog. Adding and editing products belong to
/// flows that do not exist yet.
class ProductService {
  ProductService._();

  static const productsCollection = 'products';

  /// Watches `stores/{storeId}/products`, sorted by name.
  static Stream<List<Product>> watch(String storeId) {
    return FirebaseFirestore.instance
        .collection('stores')
        .doc(storeId)
        .collection(productsCollection)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Product.fromDoc).toList());
  }
}
