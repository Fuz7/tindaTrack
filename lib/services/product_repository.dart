import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'product_service.dart';

/// How far this device's changes have got to the server.
class SyncStatus {
  const SyncStatus({required this.pending, this.lastSyncedAt});

  /// Changes made here that the server doesn't have yet.
  final int pending;

  /// When the server last confirmed it had everything from this device;
  /// null if it never has (fresh install, or offline since).
  final DateTime? lastSyncedAt;

  bool get isSynced => pending == 0 && lastSyncedAt != null;
}

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

  final _salesChanges = StreamController<List<Sale>>.broadcast();

  /// Sales history, newest first; null until [load]. Kept for
  /// [salesHistory], from this device and (after a refresh) every other.
  List<Sale>? _sales;

  /// How far back the device keeps, and fetches, sales.
  static const salesHistory = Duration(days: 60);

  /// Changes not yet handed to the server, oldest first.
  final _ops = <ProductOp>[];

  /// Set while [_flush] is sending, so two callers don't send an op twice.
  bool _flushing = false;

  final _syncChanges = StreamController<SyncStatus>.broadcast();

  /// When the server last confirmed it had everything from this device.
  DateTime? _lastSyncedAt;

  String get _key => 'products.v1.$storeId';

  List<ProductOp> get pendingOps => List.unmodifiable(_ops);

  SyncStatus get syncStatus =>
      SyncStatus(pending: _ops.length, lastSyncedAt: _lastSyncedAt);

  /// [syncStatus] straight away, then every change.
  Stream<SyncStatus> watchSyncStatus() {
    return Stream.multi((listener) {
      listener.add(syncStatus);
      final sub = _syncChanges.stream.listen(
        listener.add,
        onError: listener.addError,
      );
      listener.onCancel = sub.cancel;
    });
  }

  /// Products with a change the server doesn't have yet.
  Set<String> get pendingIds => {
    for (final op in _ops)
      if (op.sale == null) op.productId,
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

  /// Sales history, newest first: the current copy straight away (once
  /// loaded), then every change.
  Stream<List<Sale>> watchSales() {
    return Stream.multi((listener) {
      final sales = _sales;
      if (sales != null) listener.add(sales);
      final sub = _salesChanges.stream.listen(
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
    final sales = <Sale>[];
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
        for (final sale in (json['sales'] as List<dynamic>? ?? const [])) {
          sales.add(Sale.fromJson(Map<String, dynamic>.from(sale as Map)));
        }
        final synced = json['lastSyncedAt'];
        if (synced is String) _lastSyncedAt = DateTime.tryParse(synced);
      } on Object {
        // A corrupt copy is rebuilt from the server rather than crashing the
        // till; anything still queued in it is lost with it.
        products.clear();
        sales.clear();
        _ops.clear();
      }
    }
    _publish(products);
    _publishSales(sales);
    _publishSync();

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
    required Cashier cashier,
  }) async {
    final sale = Sale(
      id: remote.newId(),
      items: List.unmodifiable(items),
      receivedCentavos: receivedCentavos,
      completedAt: DateTime.now(),
      cashierUid: cashier.uid,
      cashierName: cashier.name,
    );
    if (sale.items.isEmpty) throw ArgumentError('A sale needs items.');
    if (sale.changeCentavos < 0) {
      throw ArgumentError('Received less than the total.');
    }
    _publishSales([sale, ...?_sales]);
    await _apply(ProductOp.sale(sale));
    return sale;
  }

  /// Edits a completed sale: its [items] (quantities changed or lines
  /// removed), [receivedCentavos] and [customerName] (blank clears it).
  ///
  /// Stock moves by the difference only — a line cut from 3 to 2 puts one
  /// back on the shelf — so sales made elsewhere meanwhile still count. A
  /// voided sale can't be edited. Returns the edited sale, or [original] if
  /// nothing changed.
  Future<Sale> editSale(
    Sale original, {
    required List<SaleItem> items,
    required int receivedCentavos,
    required String? customerName,
    required Cashier editor,
  }) async {
    final current =
        _sales?.where((s) => s.id == original.id).firstOrNull ?? original;
    if (current.voided) throw StateError('A refunded sale can\'t be edited.');
    if (items.isEmpty) {
      throw ArgumentError('A sale needs items; refund it instead.');
    }
    final name = customerName?.trim();
    final edited = current.copyWith(
      items: List.unmodifiable(items),
      receivedCentavos: receivedCentavos,
      customerName: () => name == null || name.isEmpty ? null : name,
      editedAt: DateTime.now(),
      editedBy: editor.name,
    );
    if (edited.changeCentavos < 0) {
      throw ArgumentError('Received less than the total.');
    }
    if (_sameSale(current, edited)) return current;

    final before = current.soldByProduct;
    final after = edited.soldByProduct;
    final restock = <String, int>{
      for (final id in {...before.keys, ...after.keys})
        if ((before[id] ?? 0) != (after[id] ?? 0))
          id: (before[id] ?? 0) - (after[id] ?? 0),
    };
    _publishSales([
      for (final s in _sales ?? const <Sale>[]) s.id == edited.id ? edited : s,
    ]);
    await _apply(ProductOp.editSale(edited, restock));
    return edited;
  }

  /// Refunds [sale]: marks it void and returns its items to stock. A sale
  /// already voided is left as it is. Returns the voided sale.
  Future<Sale> voidSale(Sale sale) async {
    final current = _sales?.where((s) => s.id == sale.id).firstOrNull ?? sale;
    if (current.voided) return current;
    final voided = current.voidedOn(DateTime.now());
    _publishSales([
      for (final s in _sales ?? const <Sale>[]) s.id == voided.id ? voided : s,
    ]);
    await _apply(ProductOp.voidSale(voided));
    return voided;
  }

  Future<void> delete(String productId) => _apply(ProductOp.delete(productId));

  Future<void> dispose() async {
    await _changes.close();
    await _salesChanges.close();
    await _syncChanges.close();
  }

  Future<void> _apply(ProductOp op) async {
    _ops.add(op);
    _publish(op.applyTo(_products ?? const []));
    _publishSync();
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
        if (_ops.isEmpty) _lastSyncedAt = DateTime.now();
        _publishSync();
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
    List<Sale>? serverSales;
    try {
      serverSales = await remote.fetchSales(
        since: DateTime.now().subtract(salesHistory),
      );
    } on Object {
      // Keep the device's sales history; products still refresh.
    }
    if (_changes.isClosed) return;

    // Ops the server already has landed on an earlier run. They go before
    // the replay below, or their stock change would be counted twice.
    final serverIds = {for (final p in server) p.id};
    final salesOnServer = {
      for (final s in serverSales ?? const <Sale>[]) s.id: s,
    };
    _ops.removeWhere((op) {
      switch (op.kind) {
        case ProductOpKind.create:
          return serverIds.contains(op.productId);
        case ProductOpKind.sale:
          return salesOnServer.containsKey(op.productId);
        case ProductOpKind.voidSale:
          return salesOnServer[op.productId]?.voided ?? false;
        case ProductOpKind.editSale:
          final landed = salesOnServer[op.productId]?.editedAt;
          return landed != null && !landed.isBefore(op.sale!.editedAt!);
        case ProductOpKind.update:
        case ProductOpKind.delete:
          return false;
      }
    });

    var products = server;
    for (final op in _ops) {
      products = op.applyTo(products);
    }
    _publish(products);
    if (serverSales != null) _mergeSales(salesOnServer);
    if (_ops.isEmpty) _lastSyncedAt = DateTime.now();
    _publishSync();
    await _persist();
    unawaited(_flush());
  }

  /// Merges the server's recent sales into the history. A sale or refund
  /// still queued here keeps this device's version.
  void _mergeSales(Map<String, Sale> onServer) {
    final queued = {
      for (final op in _ops)
        if (op.sale != null) op.productId,
    };
    final merged = {...onServer};
    for (final local in _sales ?? const <Sale>[]) {
      if (queued.contains(local.id) || !merged.containsKey(local.id)) {
        merged[local.id] = local;
      }
    }
    _publishSales(merged.values.toList());
  }

  void _publish(List<Product> products) {
    final sorted = [...products]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _products = List.unmodifiable(sorted);
    if (!_changes.isClosed) _changes.add(_products!);
  }

  /// Newest first, and only [salesHistory] back: older sales live on the
  /// server, and keeping them here would grow the device copy without end.
  void _publishSales(List<Sale> sales) {
    final cutoff = DateTime.now().subtract(salesHistory);
    final kept = sales.where((s) => s.completedAt.isAfter(cutoff)).toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    _sales = List.unmodifiable(kept);
    if (!_salesChanges.isClosed) _salesChanges.add(_sales!);
  }

  void _publishSync() {
    if (!_syncChanges.isClosed) _syncChanges.add(syncStatus);
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
        'sales': [for (final s in _sales ?? const <Sale>[]) s.toJson()],
        'lastSyncedAt': _lastSyncedAt?.toIso8601String(),
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

/// Whether an edit changed nothing that [ProductRepository.editSale] saves.
bool _sameSale(Sale a, Sale b) =>
    a.receivedCentavos == b.receivedCentavos &&
    a.customerName == b.customerName &&
    jsonEncode([for (final i in a.items) i.toJson()]) ==
        jsonEncode([for (final i in b.items) i.toJson()]);
