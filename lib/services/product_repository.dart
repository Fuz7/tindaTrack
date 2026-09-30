import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'product_service.dart';

/// A store's product catalog, kept on the device.
///
/// The app reads products from here, never live from Firestore: search and
/// the Inventory tab work the same with or without a connection. The copy is
/// saved to `SharedPreferences` as one JSON document per store, next to a
/// queue of [ProductOp]s — every add, edit and delete made on this device
/// that the server doesn't have yet.
///
/// Talking to the server is kept deliberately thin until the real offline
/// sync is built:
/// - Every change is applied to the device copy at once, queued, and the
///   queue is sent in order, stopping at the first failure. What is left is
///   retried on the next [load]. [pendingOps] is what a sync layer would pick
///   up from.
/// - [load] also refreshes the copy from the server once, in the background,
///   so changes from other devices appear; queued ops are replayed on top so
///   nothing made here is lost to that refresh.
class ProductRepository {
  ProductRepository({required this.storeId, required this.remote});

  /// The Firestore-backed repository the app uses.
  static ProductRepository forStore(String storeId) =>
      ProductRepository(storeId: storeId, remote: ProductService(storeId));

  final String storeId;

  /// The server side; Firestore in the app, a fake in tests.
  final ProductRemote remote;

  final _changes = StreamController<List<Product>>.broadcast();

  /// Null until [load] has read the device copy.
  List<Product>? _products;

  /// Changes not yet handed to the server, oldest first.
  final _ops = <ProductOp>[];

  /// Set while [_flush] is sending, so two callers don't send an op twice.
  bool _flushing = false;

  String get _key => 'products.v1.$storeId';

  List<ProductOp> get pendingOps => List.unmodifiable(_ops);

  /// Products with a change the server doesn't have yet.
  Set<String> get pendingIds => {
    for (final op in _ops)
      if (op.kind != ProductOpKind.sale) op.productId,
  };

  /// The catalog sorted by name: the current copy straight away (once
  /// loaded), then every change.
  Stream<List<Product>> watch() {
    return Stream.multi((listener) {
      // Subscribing and replaying synchronously leaves no gap for a change
      // to slip between the two.
      final products = _products;
      if (products != null) listener.add(products);
      final sub = _changes.stream.listen(
        listener.add,
        onError: listener.addError,
      );
      listener.onCancel = sub.cancel;
    });
  }

  /// Reads the device copy, then — without holding anything up — refreshes
  /// it from the server and sends queued changes. Offline, the second half
  /// fails quietly and the device copy stands.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final products = <Product>[];
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        for (final item in json['products'] as List<dynamic>) {
          final map = Map<String, dynamic>.from(item as Map);
          products.add(Product.fromMap(map['id'] as String, map));
        }
        for (final op in (json['ops'] as List<dynamic>? ?? const [])) {
          _ops.add(ProductOp.fromJson(Map<String, dynamic>.from(op as Map)));
        }
        // Copies saved before the op queue kept only the ids of unsent new
        // products.
        for (final id in (json['pending'] as List<dynamic>? ?? const [])) {
          final product = products.where((p) => p.id == id).firstOrNull;
          if (product != null) _ops.add(ProductOp.create(product));
        }
      } on Object {
        // A corrupt copy is rebuilt from the server rather than crashing the
        // till; anything still queued in it is lost with it.
        products.clear();
        _ops.clear();
      }
    }
    _publish(products);

    unawaited(_refreshFromServer());
  }

  /// Saves a new product. The returned future completes once the device copy
  /// is written — it does not wait for, or fail with, the server.
  Future<Product> add(ProductDraft draft) async {
    final product = draft.toProduct(remote.newId());
    await _apply(ProductOp.create(product));
    return product;
  }

  /// Saves the edits that turn [original] — the product as the edit form
  /// opened it — into [draft].
  ///
  /// Only changed fields are sent, and stock as the difference the owner
  /// made: if another device sold two while the form was open, both changes
  /// count instead of this save erasing that sale.
  Future<void> update(Product original, ProductDraft draft) async {
    final before = original.toMap();
    final after = draft.toProduct(original.id).toMap()
      ..['imageUrl'] = original.imageUrl; // not editable yet
    final fields = <String, dynamic>{
      for (final key in after.keys)
        if (key != 'stock' && !_same(before[key], after[key])) key: after[key],
    };
    final delta = draft.stock - original.stock;
    if (fields.isEmpty && delta == 0) return;
    await _apply(
      ProductOp.update(original.id, fields: fields, stockDelta: delta),
    );
  }

  /// Sets [original]'s stock to [newStock] — a recount, a delivery, or a
  /// loss — recorded as the difference from [original.stock], the count the
  /// owner was looking at, so sales made elsewhere meanwhile still count.
  ///
  /// Every update also leaves a [StockAdjustment] log entry. A decrease
  /// must say why: [reason] is required then, and [note] too for
  /// [StockReason.other].
  Future<void> adjustStock(
    Product original,
    int newStock, {
    StockReason? reason,
    String? note,
  }) async {
    final delta = newStock - original.stock;
    if (delta == 0) return;
    if (delta < 0 && reason == null) {
      throw ArgumentError.notNull('reason');
    }
    final trimmed = note?.trim();
    if (reason == StockReason.other && (trimmed == null || trimmed.isEmpty)) {
      throw ArgumentError('A note is required when the reason is "Other".');
    }
    await _apply(
      ProductOp.update(
        original.id,
        stockDelta: delta,
        adjustment: StockAdjustment(
          id: remote.newId(),
          productName: original.name,
          before: original.stock,
          after: newStock,
          reason: delta < 0 ? reason : null,
          note: trimmed == null || trimmed.isEmpty ? null : trimmed,
        ),
      ),
    );
  }

  /// Records a completed sale and takes each sold product's stock down by
  /// its quantity, on the device at once and on the server when it can.
  /// Returns the sale as recorded.
  Future<Sale> recordSale({
    required List<SaleItem> items,
    required int receivedCentavos,
  }) async {
    final sale = Sale(
      id: remote.newId(),
      items: List.unmodifiable(items),
      receivedCentavos: receivedCentavos,
      completedAt: DateTime.now(),
    );
    if (sale.items.isEmpty) throw ArgumentError('A sale needs items.');
    if (sale.changeCentavos < 0) {
      throw ArgumentError('Received less than the total.');
    }
    await _apply(ProductOp.sale(sale));
    return sale;
  }

  Future<void> delete(String productId) => _apply(ProductOp.delete(productId));

  Future<void> dispose() => _changes.close();

  Future<void> _apply(ProductOp op) async {
    _ops.add(op);
    _publish(op.applyTo(_products ?? const []));
    await _persist();
    unawaited(_flush());
  }

  /// Sends queued ops in order. Order matters — an edit can't reach the
  /// server before the product it edits — so the first failure stops the
  /// run, and the rest wait for the next [load].
  Future<void> _flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      while (_ops.isNotEmpty && !_changes.isClosed) {
        final op = _ops.first;
        try {
          await remote.send(op);
        } on ProductMissing {
          // Deleted elsewhere: this op can never land.
        } on Object {
          return; // Offline or refused; try again next load.
        }
        _ops.remove(op);
        await _persist();
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _refreshFromServer() async {
    final List<Product> server;
    try {
      server = await remote.fetchAll();
    } on Object {
      return; // Offline, or refused: keep the device copy.
    }
    if (_changes.isClosed) return;

    // A queued create the server already has landed on an earlier run.
    final serverIds = {for (final p in server) p.id};
    _ops.removeWhere(
      (op) =>
          op.kind == ProductOpKind.create && serverIds.contains(op.productId),
    );
    var products = server;
    for (final op in _ops) {
      products = op.applyTo(products);
    }
    _publish(products);
    await _persist();
    unawaited(_flush());
  }

  void _publish(List<Product> products) {
    final sorted = [...products]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _products = List.unmodifiable(sorted);
    if (!_changes.isClosed) _changes.add(_products!);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'products': [
          for (final p in _products ?? const <Product>[])
            {'id': p.id, ...p.toMap()},
        ],
        'ops': [for (final op in _ops) op.toJson()],
      }),
    );
  }
}

/// Field equality for [ProductRepository.update]; lists compare by items.
bool _same(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  return a == b;
}
