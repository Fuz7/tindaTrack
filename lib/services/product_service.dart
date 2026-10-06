import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// The most a product photo may weigh.
///
/// A Firestore document stops at 1 MiB, and a photo gets a document to
/// itself, so this is a guard against a pathological image rather than a
/// normal limit: the picker is asked for 512px at quality 70, which lands
/// around 40 KB. Keeping photos small also keeps a whole catalog inside the
/// 40 MB Firestore keeps cached on each phone.
const maxProductImageBytes = 200 * 1024;

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
    this.size,
    this.sku,
    this.categories = const [],
    this.imageUrl,
    this.imageBytes,
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

  /// The product photo, joined in by [ProductRepository] from the store's
  /// `productImages` collection.
  ///
  /// Not a field of the product document — [toMap] leaves it out — so a
  /// price or stock change never re-sends the photo to every other phone.
  final Uint8List? imageBytes;

  /// Whether the product can be flagged LOW STOCK and counted in the
  /// Inventory alerts. Off for items the store keeps but rarely sells, so
  /// they don't bury the ones that matter.
  final bool stockAlerts;

  /// The main category: the one the SKU is built from.
  String? get mainCategory => categories.isEmpty ? null : categories.first;

  /// The name with its size, for the cart and anywhere else one line has to
  /// tell sizes apart: `Piattos Cheese · 40g`.
  String get displayName => size == null ? name : '$name · $size';

  /// This product with [bytes] as its photo; used by [ProductRepository] to
  /// join the `productImages` listener onto the catalog.
  Product withImage(Uint8List? bytes) => Product(
    id: id,
    name: name,
    stock: stock,
    sellCentavos: sellCentavos,
    buyCentavos: buyCentavos,
    size: size,
    sku: sku,
    categories: categories,
    imageUrl: imageUrl,
    imageBytes: bytes,
    stockAlerts: stockAlerts,
  );

  /// Every stored field but [id], which is the document key. [imageBytes] is
  /// deliberately absent: the photo lives in its own document.
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

/// What a save does to a product's photo.
///
/// A null [ProductDraft.image] means the form left the photo alone, which is
/// not the same as [ImageChange.remove] — the first writes nothing, the
/// second deletes the photo document.
class ImageChange {
  /// Replaces the photo with [bytes].
  const ImageChange(Uint8List this.bytes);

  /// Deletes the photo.
  const ImageChange.remove() : bytes = null;

  final Uint8List? bytes;

  bool get removes => bytes == null;
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
    this.image,
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

  /// What to do with the photo, or null to leave it as it is.
  final ImageChange? image;

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

/// One line of a completed sale, frozen as it was rung up: a later rename
/// or price change leaves the record of what was sold alone.
class SaleItem {
  const SaleItem({
    required this.name,
    required this.unitCentavos,
    required this.quantity,
    this.productId,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
    productId: json['productId'] as String?,
    name: json['name'] as String,
    unitCentavos: (json['unitCentavos'] as num).round(),
    quantity: (json['quantity'] as num).round(),
  );

  /// The inventory product sold; null for a keypad "Manual Entry", which
  /// moves no stock.
  final String? productId;
  final String name;
  final int unitCentavos;
  final int quantity;

  int get totalCentavos => unitCentavos * quantity;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'name': name,
    'unitCentavos': unitCentavos,
    'quantity': quantity,
  };
}

/// Who rang up, or last edited, a sale.
///
/// Staff accounts are a Pro feature that isn't built yet, so for now
/// everyone signed in to a store is its owner, named after their Google
/// account — or "Owner" when the account carries no name.
class Cashier {
  const Cashier({required this.uid, required this.name});

  const Cashier.owner(String uid, {String? name})
    : this(uid: uid, name: name ?? 'Owner');

  final String uid;
  final String name;
}

/// A completed sale, as recorded in `stores/{storeId}/sales/{id}` for the
/// Transactions and Analytics tabs to come.
class Sale {
  const Sale({
    required this.id,
    required this.items,
    required this.receivedCentavos,
    required this.completedAt,
    this.paymentMethod = 'cash',
    this.customerName,
    this.cashierUid,
    this.cashierName,
    this.voidedAt,
    this.editedAt,
    this.editedBy,
  });

  factory Sale.fromJson(Map<String, dynamic> json) {
    DateTime? time(String key) => json[key] is num
        ? DateTime.fromMillisecondsSinceEpoch((json[key] as num).round())
        : null;
    String? text(String key) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    return Sale(
      id: json['id'] as String,
      items: [
        for (final item in json['items'] as List<dynamic>)
          SaleItem.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      receivedCentavos: (json['receivedCentavos'] as num).round(),
      completedAt: time('completedAt')!,
      paymentMethod: text('paymentMethod') ?? 'cash',
      customerName: text('customerName'),
      cashierUid: text('cashierUid'),
      cashierName: text('cashierName'),
      voidedAt: time('voidedAt'),
      editedAt: time('editedAt'),
      editedBy: text('editedBy'),
    );
  }

  final String id;
  final List<SaleItem> items;

  /// Cash handed over; at least [totalCentavos].
  final int receivedCentavos;

  /// This device's clock when the sale was completed. The server also stamps
  /// its own time, but a sale made offline belongs to when it happened.
  final DateTime completedAt;
  final String paymentMethod;

  /// Optional; checkout doesn't ask, but an edit can add it.
  final String? customerName;

  /// Who rang it up. Null on sales recorded before cashiers were kept.
  final String? cashierUid;
  final String? cashierName;

  /// When the sale was refunded, voiding it: its items went back to stock
  /// and it no longer counts toward sales. Null for a standing sale.
  final DateTime? voidedAt;

  /// The last edit, and the cashier name of who made it.
  final DateTime? editedAt;
  final String? editedBy;

  bool get voided => voidedAt != null;

  /// A short code to read out or search by: `TX-` and the id's first six
  /// characters.
  String get code =>
      'TX-${id.substring(0, id.length < 6 ? id.length : 6).toUpperCase()}';

  Sale copyWith({
    List<SaleItem>? items,
    int? receivedCentavos,
    String? Function()? customerName,
    DateTime? voidedAt,
    DateTime? editedAt,
    String? editedBy,
  }) => Sale(
    id: id,
    items: items ?? this.items,
    receivedCentavos: receivedCentavos ?? this.receivedCentavos,
    completedAt: completedAt,
    paymentMethod: paymentMethod,
    customerName: customerName == null ? this.customerName : customerName(),
    cashierUid: cashierUid,
    cashierName: cashierName,
    voidedAt: voidedAt ?? this.voidedAt,
    editedAt: editedAt ?? this.editedAt,
    editedBy: editedBy ?? this.editedBy,
  );

  Sale voidedOn(DateTime at) => copyWith(voidedAt: at);

  int get totalCentavos =>
      items.fold(0, (total, item) => total + item.totalCentavos);
  int get changeCentavos => receivedCentavos - totalCentavos;
  int get itemCount => items.fold(0, (total, item) => total + item.quantity);

  /// Units sold per inventory product; manual entries move no stock.
  Map<String, int> get soldByProduct {
    final sold = <String, int>{};
    for (final item in items) {
      final id = item.productId;
      if (id == null) continue;
      sold.update(id, (n) => n + item.quantity, ifAbsent: () => item.quantity);
    }
    return sold;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'items': [for (final item in items) item.toJson()],
    'receivedCentavos': receivedCentavos,
    'completedAt': completedAt.millisecondsSinceEpoch,
    'paymentMethod': paymentMethod,
    'customerName': customerName,
    'cashierUid': cashierUid,
    'cashierName': cashierName,
    'voidedAt': voidedAt?.millisecondsSinceEpoch,
    'editedAt': editedAt?.millisecondsSinceEpoch,
    'editedBy': editedBy,
  };
}

enum ProductOpKind { create, update, delete, sale, voidSale, editSale }

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
    this.sale,
    this.image,
  ]);

  /// [product] as a whole, opening stock included: the document is new, so
  /// there is no concurrent count to lose.
  ProductOp.create(Product product, {ImageChange? image})
    : this._(
        ProductOpKind.create,
        product.id,
        product.toMap(),
        0,
        null,
        null,
        image,
      );

  const ProductOp.update(
    String productId, {
    Map<String, dynamic> fields = const {},
    int stockDelta = 0,
    StockAdjustment? adjustment,
    ImageChange? image,
  }) : this._(
         ProductOpKind.update,
         productId,
         fields,
         stockDelta,
         adjustment,
         null,
         image,
       );

  const ProductOp.delete(String productId)
    : this._(ProductOpKind.delete, productId, const {}, 0);

  /// A completed sale: recorded, and every inventory line's stock taken
  /// down by its quantity. Keyed by the sale's id, since it touches many
  /// products.
  ProductOp.sale(Sale sale)
    : this._(ProductOpKind.sale, sale.id, const {}, 0, null, sale);

  /// A refund: [sale] (already marked voided) is recorded as void, and its
  /// inventory lines go back to stock.
  ProductOp.voidSale(Sale sale)
    : this._(ProductOpKind.voidSale, sale.id, const {}, 0, null, sale);

  /// An edit to a completed sale: [sale] is the edited version, and
  /// [restock] the units per product going back to stock (negative when a
  /// quantity went up and more left the shelf).
  ProductOp.editSale(Sale sale, Map<String, int> restock)
    : this._(ProductOpKind.editSale, sale.id, restock, 0, null, sale);

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
    json['sale'] == null
        ? null
        : Sale.fromJson(Map<String, dynamic>.from(json['sale'] as Map)),
  );

  final ProductOpKind kind;
  final String productId;

  /// For a create, the whole product ([Product.toMap]); for an update, only
  /// the changed fields; for a sale edit, units restocked per product id;
  /// empty otherwise.
  final Map<String, dynamic> fields;
  final int stockDelta;

  /// Set on a direct stock update: the log entry it leaves alongside.
  final StockAdjustment? adjustment;

  /// Set on a sale op.
  final Sale? sale;

  /// Set on a create or update that changes the product's photo.
  final ImageChange? image;

  /// [image] is left out: this JSON exists only for the ops left behind by
  /// the app's old on-device queue, which predate photos entirely.
  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'productId': productId,
    'fields': fields,
    'stockDelta': stockDelta,
    if (adjustment != null) 'adjustment': adjustment!.toJson(),
    if (sale != null) 'sale': sale!.toJson(),
  };

  /// [products] with this change applied — what [ProductService.send]'s
  /// writes do to the catalog. Tests' stand-in server uses it to act like
  /// Firestore.
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
      case ProductOpKind.sale:
        final sold = sale!.soldByProduct;
        return [
          for (final p in products)
            if (!sold.containsKey(p.id))
              p
            else
              Product.fromMap(p.id, {
                ...p.toMap(),
                'stock': p.stock - sold[p.id]!,
              }),
        ];
      case ProductOpKind.voidSale:
        final returned = sale!.soldByProduct;
        return [
          for (final p in products)
            if (!returned.containsKey(p.id))
              p
            else
              Product.fromMap(p.id, {
                ...p.toMap(),
                'stock': p.stock + returned[p.id]!,
              }),
        ];
      case ProductOpKind.editSale:
        return [
          for (final p in products)
            if (fields[p.id] is! int)
              p
            else
              Product.fromMap(p.id, {
                ...p.toMap(),
                'stock': p.stock + (fields[p.id] as int),
              }),
        ];
    }
  }
}

/// One answer from a live listener: the data, plus how it relates to the
/// server.
class RemoteSnapshot<T> {
  const RemoteSnapshot(
    this.data, {
    this.pendingIds = const {},
    this.fromCache = false,
  });

  final T data;

  /// Documents in [data] carrying a change from this device that the server
  /// hasn't confirmed yet.
  final Set<String> pendingIds;

  /// Whether this came from the phone's cache rather than the server — in
  /// practice, whether the device is offline.
  final bool fromCache;
}

/// The server side of a store's catalog, as [ProductRepository] sees it.
/// An interface so tests can stand in for Firestore.
abstract interface class ProductRemote {
  /// A fresh id, made on the device so it works offline.
  String newId();

  /// Every product, live: what the phone has cached at once (offline too),
  /// then every change from this device or another.
  Stream<RemoteSnapshot<List<Product>>> watchProducts();

  /// Sales completed on or after [since], live, as [watchProducts].
  Stream<RemoteSnapshot<List<Sale>>> watchSales({required DateTime since});

  /// Every product photo in the store by product id, live, as
  /// [watchProducts] — same cache, same queue. Kept apart from the products
  /// so a stock change doesn't re-send the photos with it.
  Stream<RemoteSnapshot<Map<String, Uint8List>>> watchImages();

  /// Writes [op]. It shows in [watchProducts] / [watchSales] at once, and
  /// reaches the server when it can — offline, once the connection is back.
  /// Completing means it's queued; it must not be sent again, or a stock
  /// change would count twice.
  Future<void> send(ProductOp op);
}

/// [ProductRemote] backed by `stores/{storeId}/products` in Firestore.
class ProductService implements ProductRemote {
  ProductService(this.storeId);

  static const productsCollection = 'products';
  static const imagesCollection = 'productImages';

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

  /// Completed sales, for Transactions and Analytics.
  CollectionReference<Map<String, dynamic>> get _sales => FirebaseFirestore
      .instance
      .collection('stores')
      .doc(storeId)
      .collection('sales');

  /// Product photos, one document per product, keyed by the product's id.
  ///
  /// Apart from the product so the catalog listener — which fires on every
  /// sale — carries counts and prices only. Photos change almost never, so
  /// each phone fetches one once and then reads it from the Firestore cache.
  CollectionReference<Map<String, dynamic>> get _images => FirebaseFirestore
      .instance
      .collection('stores')
      .doc(storeId)
      .collection(imagesCollection);

  /// Writes a photo change: bytes replace the document, a removal deletes
  /// it. Separate from the product's own write, so a photo that fails
  /// doesn't take the product's details down with it.
  Future<void> _sendImage(String productId, ImageChange change) {
    final doc = _images.doc(productId);
    final bytes = change.bytes;
    if (bytes == null) return doc.delete();
    return doc.set({
      'bytes': Blob(bytes),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// The sale record, then each sold product's stock taken down by an
  /// increment. Separate writes rather than one batch on purpose: a product
  /// deleted on another device fails only its own stock write, instead of
  /// taking the record of the sale down with it. The record's id is fixed on
  /// the device, so a resend overwrites rather than duplicates it.
  Future<void> _sendSale(Sale sale) {
    final writes = <Future<void>>[
      _sales.doc(sale.id).set({
        ...sale.toJson()..remove('id'),
        'totalCentavos': sale.totalCentavos,
        'changeCentavos': sale.changeCentavos,
        'itemCount': sale.itemCount,
        'createdAt': FieldValue.serverTimestamp(),
      }),
    ];
    for (final MapEntry(key: id, value: quantity)
        in sale.soldByProduct.entries) {
      writes.add(
        _products.doc(id).update({
          'stock': FieldValue.increment(-quantity),
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );
    }
    return Future.wait(writes);
  }

  /// Marks the sale void, then returns each product's units with an
  /// increment — separate writes, for the same reason as [_sendSale].
  Future<void> _sendVoid(Sale sale) {
    return Future.wait([
      _sales.doc(sale.id).update({
        'voidedAt': sale.voidedAt!.millisecondsSinceEpoch,
        'voidedAtServer': FieldValue.serverTimestamp(),
      }),
      for (final MapEntry(key: id, value: quantity)
          in sale.soldByProduct.entries)
        _products.doc(id).update({
          'stock': FieldValue.increment(quantity),
          'updatedAt': FieldValue.serverTimestamp(),
        }),
    ]);
  }

  /// Rewrites the sale's editable parts, then moves each product's stock by
  /// its [restock] difference — separate writes, as in [_sendSale].
  Future<void> _sendEdit(Sale sale, Map<String, int> restock) {
    return Future.wait([
      _sales.doc(sale.id).update({
        'items': [for (final item in sale.items) item.toJson()],
        'receivedCentavos': sale.receivedCentavos,
        'totalCentavos': sale.totalCentavos,
        'changeCentavos': sale.changeCentavos,
        'itemCount': sale.itemCount,
        'customerName': sale.customerName,
        'editedAt': sale.editedAt?.millisecondsSinceEpoch,
        'editedBy': sale.editedBy,
        'editedAtServer': FieldValue.serverTimestamp(),
      }),
      for (final MapEntry(key: id, value: units) in restock.entries)
        if (units != 0)
          _products.doc(id).update({
            'stock': FieldValue.increment(units),
            'updatedAt': FieldValue.serverTimestamp(),
          }),
    ]);
  }

  /// Firestore answers from its on-phone cache first — offline, that is the
  /// whole answer — then keeps the list live. Its local writes show at once,
  /// before the server confirms them. `includeMetadataChanges` makes it
  /// report when a write is confirmed or the connection drops or returns,
  /// even when no data changed; that is what Sync Status reads.
  @override
  Stream<RemoteSnapshot<List<Product>>> watchProducts() => _products
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => RemoteSnapshot(
          [for (final doc in snapshot.docs) Product.fromDoc(doc)],
          pendingIds: _pending(snapshot),
          fromCache: snapshot.metadata.isFromCache,
        ),
      );

  /// As [watchProducts], for the sales since [since]. A malformed sale is
  /// skipped rather than taking the whole history down.
  @override
  Stream<RemoteSnapshot<List<Sale>>> watchSales({required DateTime since}) =>
      _sales
          .where(
            'completedAt',
            isGreaterThanOrEqualTo: since.millisecondsSinceEpoch,
          )
          .snapshots(includeMetadataChanges: true)
          .map(
            (snapshot) => RemoteSnapshot(
              [for (final doc in snapshot.docs) ?_saleOf(doc)],
              pendingIds: _pending(snapshot),
              fromCache: snapshot.metadata.isFromCache,
            ),
          );

  /// As [watchProducts], for the store's photos. A document whose `bytes`
  /// is missing or malformed is skipped, leaving that product's placeholder.
  @override
  Stream<RemoteSnapshot<Map<String, Uint8List>>> watchImages() => _images
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => RemoteSnapshot(
          {
            for (final doc in snapshot.docs)
              if (doc.data()['bytes'] case final Blob blob) doc.id: blob.bytes,
          },
          pendingIds: _pending(snapshot),
          fromCache: snapshot.metadata.isFromCache,
        ),
      );

  static Set<String> _pending(QuerySnapshot<Map<String, dynamic>> snapshot) => {
    for (final doc in snapshot.docs)
      if (doc.metadata.hasPendingWrites) doc.id,
  };

  static Sale? _saleOf(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      return Sale.fromJson({...doc.data(), 'id': doc.id});
    } on Object catch (error) {
      debugPrint('Skipping malformed sale ${doc.id}: $error');
      return null;
    }
  }

  /// Generated on the device, so it works with no connection.
  @override
  String newId() => _products.doc().id;

  /// Firestore keeps its own durable queue of writes — on the phone, through
  /// restarts — and delivers them when it can, so an op is "sent" once it's
  /// queued there. Waiting for the server as well would stall every save
  /// while offline.
  ///
  /// A refusal (security rules) arrives later and is only logged; Firestore
  /// itself rolls the change back, and the live lists show the server's
  /// version again.
  @override
  Future<void> send(ProductOp op) async {
    final doc = _products.doc(op.productId);
    final Future<void> write;
    switch (op.kind) {
      case ProductOpKind.create:
        write = Future.wait([
          doc.set({...op.fields, 'createdAt': FieldValue.serverTimestamp()}),
          if (op.image case final change?) _sendImage(op.productId, change),
        ]);
      case ProductOpKind.update:
        final update = {
          ...op.fields,
          if (op.stockDelta != 0) 'stock': FieldValue.increment(op.stockDelta),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        final photo = op.image == null
            ? null
            : _sendImage(op.productId, op.image!);
        final adjustment = op.adjustment;
        if (adjustment == null) {
          // Nothing but a photo change leaves the product document alone.
          write = op.fields.isEmpty && op.stockDelta == 0 && photo != null
              ? photo
              : Future.wait([doc.update(update), ?photo]);
        } else {
          // One batch: the count and its log entry land together or not at
          // all. The entry's id is fixed on the device, so a resend
          // overwrites it rather than logging the change twice.
          final logged =
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
          write = photo == null ? logged : Future.wait([logged, photo]);
        }
      case ProductOpKind.delete:
        // The photo goes with the product, so deleting one can't leave the
        // other stranded in the store's data.
        write = Future.wait([doc.delete(), _images.doc(op.productId).delete()]);
      case ProductOpKind.sale:
        write = _sendSale(op.sale!);
      case ProductOpKind.voidSale:
        write = _sendVoid(op.sale!);
      case ProductOpKind.editSale:
        write = _sendEdit(op.sale!, {
          for (final MapEntry(:key, :value) in op.fields.entries)
            key: value as int,
        });
    }
    unawaited(
      write.catchError((Object error) {
        debugPrint('Product ${op.kind.name} ${op.productId} failed: $error');
      }),
    );
  }
}
