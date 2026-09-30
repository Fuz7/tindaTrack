import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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

/// Why stock was taken down by hand. Required for a decrease, so losses can
/// be told apart later — what goes back to the supplier, what was written
/// off — in returns and analytics.
enum StockReason {
  damaged('Damaged / Broken'),
  defective('Defective'),
  expired('Expired'),
  lost('Lost / Missing'),
  recount('Recount correction'),
  other('Other');

  const StockReason(this.label);
  final String label;
}

/// The record a direct stock update leaves in
/// `stores/{storeId}/stockAdjustments/{id}`, for returns and analytics.
///
/// The name and counts are as this device saw them when the update was
/// made, so the entry still reads right after a rename or later sales.
class StockAdjustment {
  const StockAdjustment({
    required this.id,
    required this.productName,
    required this.before,
    required this.after,
    this.reason,
    this.note,
  });

  factory StockAdjustment.fromJson(Map<String, dynamic> json) =>
      StockAdjustment(
        id: json['id'] as String,
        productName: json['productName'] as String,
        before: (json['before'] as num).round(),
        after: (json['after'] as num).round(),
        reason: json['reason'] == null
            ? null
            : StockReason.values.byName(json['reason'] as String),
        note: json['note'] as String?,
      );

  final String id;
  final String productName;
  final int before;
  final int after;

  /// Required when [after] is below [before]; null for an increase.
  final StockReason? reason;
  final String? note;

  int get delta => after - before;

  Map<String, dynamic> toJson() => {
    'id': id,
    'productName': productName,
    'before': before,
    'after': after,
    'reason': reason?.name,
    'note': note,
  };
}

enum ProductOpKind { create, update, delete }

/// One change to the catalog made on this device, queued until the server
/// has it — the unit a sync layer works in.
///
/// Updates carry only the fields that changed, and stock as a [stockDelta]
/// rather than a new count: two devices adjusting the same product then
/// combine instead of the later one erasing the earlier.
class ProductOp {
  const ProductOp._(
    this.kind,
    this.productId,
    this.fields,
    this.stockDelta, [
    this.adjustment,
  ]);

  /// [product] as a whole, opening stock included: the document is new, so
  /// there is no concurrent count to lose.
  ProductOp.create(Product product)
    : this._(ProductOpKind.create, product.id, product.toMap(), 0);

  const ProductOp.update(
    String productId, {
    Map<String, dynamic> fields = const {},
    int stockDelta = 0,
    StockAdjustment? adjustment,
  }) : this._(ProductOpKind.update, productId, fields, stockDelta, adjustment);

  const ProductOp.delete(String productId)
    : this._(ProductOpKind.delete, productId, const {}, 0);

  factory ProductOp.fromJson(Map<String, dynamic> json) => ProductOp._(
    ProductOpKind.values.byName(json['kind'] as String),
    json['productId'] as String,
    Map<String, dynamic>.from(json['fields'] as Map),
    (json['stockDelta'] as num).round(),
    json['adjustment'] == null
        ? null
        : StockAdjustment.fromJson(
            Map<String, dynamic>.from(json['adjustment'] as Map),
          ),
  );

  final ProductOpKind kind;
  final String productId;

  /// For a create, the whole product ([Product.toMap]); for an update, only
  /// the changed fields; empty for a delete.
  final Map<String, dynamic> fields;
  final int stockDelta;

  /// Set on a direct stock update: the log entry it leaves alongside.
  final StockAdjustment? adjustment;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'productId': productId,
    'fields': fields,
    'stockDelta': stockDelta,
    if (adjustment != null) 'adjustment': adjustment!.toJson(),
  };

  /// [products] with this change applied, as the device sees it.
  List<Product> applyTo(List<Product> products) {
    switch (kind) {
      case ProductOpKind.create:
        return [
          for (final p in products)
            if (p.id != productId) p,
          Product.fromMap(productId, fields),
        ];
      case ProductOpKind.delete:
        return [
          for (final p in products)
            if (p.id != productId) p,
        ];
      case ProductOpKind.update:
        return [
          for (final p in products)
            if (p.id != productId)
              p
            else
              Product.fromMap(productId, {
                ...p.toMap(),
                ...fields,
                'stock': p.stock + stockDelta,
              }),
        ];
    }
  }
}

/// The server no longer has a product an op refers to — deleted from
/// another device, say. The op can't ever land and should be dropped.
class ProductMissing implements Exception {
  const ProductMissing(this.productId);
  final String productId;

  @override
  String toString() => 'ProductMissing($productId)';
}

/// The server side of a store's catalog, as [ProductRepository] sees it.
/// An interface so tests, and the offline sync to come, can stand in for
/// Firestore.
abstract interface class ProductRemote {
  /// A fresh id for a product that may not reach the server for a while.
  String newId();

  /// The whole catalog, once. Throws if the server can't be reached.
  Future<List<Product>> fetchAll();

  /// Hands [op] over for delivery. Completing means the op is safely on its
  /// way — it must not be sent again, or a stock delta would count twice.
  /// Throws if it could not be handed over (try again later), or
  /// [ProductMissing] if it never can be.
  Future<void> send(ProductOp op);
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

  /// The stock adjustment log: one entry per direct stock update.
  CollectionReference<Map<String, dynamic>> get _adjustments =>
      FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('stockAdjustments');

  /// Generated on the device, so it works with no connection.
  @override
  String newId() => _products.doc().id;

  /// The server's catalog, with any of this device's writes still in
  /// Firestore's queue already applied — so a fresh edit isn't briefly
  /// undone by a fetch that beats it to the server.
  ///
  /// An answer from Firestore's cache alone counts as offline: on a fresh
  /// install that cache is empty, and would wipe the device copy.
  @override
  Future<List<Product>> fetchAll() async {
    final snapshot = await _products.get();
    if (snapshot.metadata.isFromCache) {
      throw StateError('Offline: only a cached catalog was available.');
    }
    return snapshot.docs.map(Product.fromDoc).toList();
  }

  /// Firestore keeps its own durable queue of writes and delivers them when
  /// it can, so an op is "sent" once it's queued there — waiting for the
  /// server as well would mean an op queued just before the app closed gets
  /// queued again on the next launch, and its stock delta applied twice.
  ///
  /// A refusal (security rules) arrives later and is only logged; the next
  /// catalog refresh then shows the server's version.
  @override
  Future<void> send(ProductOp op) async {
    final doc = _products.doc(op.productId);
    final Future<void> write;
    switch (op.kind) {
      case ProductOpKind.create:
        write = doc.set({
          ...op.fields,
          'createdAt': FieldValue.serverTimestamp(),
        });
      case ProductOpKind.update:
        final update = {
          ...op.fields,
          if (op.stockDelta != 0) 'stock': FieldValue.increment(op.stockDelta),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        final adjustment = op.adjustment;
        if (adjustment == null) {
          write = doc.update(update);
        } else {
          // One batch: the count and its log entry land together or not at
          // all. The entry's id is fixed on the device, so a resend
          // overwrites it rather than logging the change twice.
          write =
              (FirebaseFirestore.instance.batch()
                    ..update(doc, update)
                    ..set(_adjustments.doc(adjustment.id), {
                      'productId': op.productId,
                      'productName': adjustment.productName,
                      'delta': adjustment.delta,
                      'before': adjustment.before,
                      'after': adjustment.after,
                      'reason': adjustment.reason?.name,
                      'note': adjustment.note,
                      'createdAt': FieldValue.serverTimestamp(),
                    }))
                  .commit();
        }
      case ProductOpKind.delete:
        write = doc.delete();
    }
    unawaited(
      write.catchError((Object error) {
        debugPrint('Product ${op.kind.name} ${op.productId} failed: $error');
      }),
    );
  }
}
