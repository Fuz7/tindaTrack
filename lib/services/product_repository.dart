import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'product_service.dart';

/// How this device's changes stand with the server, as Firestore reports it.
class SyncStatus {
  const SyncStatus({
    required this.pending,
    required this.online,
    this.lastSyncedAt,
  });

  /// Products and sales carrying a change from this device that the server
  /// hasn't confirmed yet. Firestore holds them on the phone, through
  /// restarts, and sends them when it can.
  final int pending;

  /// Whether the latest data came from the server rather than the phone's
  /// cache — in practice, whether the device is online.
  final bool online;

  /// When everything was last confirmed by the server, this session; null
  /// until then.
  final DateTime? lastSyncedAt;

  bool get isSynced => online && pending == 0;
}

/// A store's products and sales, live from Firestore.
///
/// There is no copy of its own: Firestore keeps its own cache and write
/// queue on the phone, so the lists show offline (from that cache), changes
/// made offline show at once and reach the server when the connection is
/// back, and changes from other phones arrive by themselves while online.
///
/// What this adds on top is the store's rules for a change — only changed
/// fields sent, stock as a difference, a reason for a decrease, a sale's
/// edit as a restock — and one listener per list, shared by every tab.
class ProductRepository {
  ProductRepository({required this.storeId, required this.remote});

  /// The Firestore-backed repository the app uses.
  static ProductRepository forStore(String storeId) =>
      ProductRepository(storeId: storeId, remote: ProductService(storeId));

  final String storeId;

  /// The server side; Firestore in the app, a fake in tests.
  final ProductRemote remote;

  /// How far back sales are listened to — what Transactions and Analytics
  /// can show.
  static const salesHistory = Duration(days: 60);

  final _changes = StreamController<List<Product>>.broadcast();
  final _salesChanges = StreamController<List<Sale>>.broadcast();
  final _syncChanges = StreamController<SyncStatus>.broadcast();

  /// The latest from each listener; null until it first answers.
  RemoteSnapshot<List<Product>>? _productSnapshot;
  RemoteSnapshot<List<Sale>>? _saleSnapshot;

  /// Sorted copies of the above, as [watch] and [watchSales] hand them out.
  List<Product>? _products;
  List<Sale>? _sales;

  DateTime? _lastSyncedAt;

  StreamSubscription<RemoteSnapshot<List<Product>>>? _productsSub;
  StreamSubscription<RemoteSnapshot<List<Sale>>>? _salesSub;

  /// Completes with the first sales answer; the leftover ops of the old
  /// on-device copy are checked against it.
  final _firstSales = Completer<void>();

  /// Null until both listeners have answered.
  SyncStatus? get syncStatus {
    final products = _productSnapshot;
    final sales = _saleSnapshot;
    if (products == null || sales == null) return null;
    return SyncStatus(
      pending: products.pendingIds.length + sales.pendingIds.length,
      online: !products.fromCache && !sales.fromCache,
      lastSyncedAt: _lastSyncedAt,
    );
  }

  /// [syncStatus] once known, then every change.
  Stream<SyncStatus> watchSyncStatus() => _replay(_syncChanges, syncStatus);

  /// The catalog sorted by name: the latest straight away (once loaded),
  /// then every change, from this device or another.
  Stream<List<Product>> watch() => _replay(_changes, _products);

  /// Sales of the last [salesHistory], newest first: the latest straight
  /// away (once loaded), then every change.
  Stream<List<Sale>> watchSales() => _replay(_salesChanges, _sales);

  /// Starts listening to Firestore. Offline, the first answers come from
  /// the phone's cache.
  Future<void> load() async {
    _productsSub = remote.watchProducts().listen(
      _onProducts,
      onError: _changes.addError,
    );
    _salesSub = remote
        .watchSales(since: DateTime.now().subtract(salesHistory))
        .listen(_onSales, onError: _onSalesError);
    await _sendLeftoverOps();
  }

  /// Saves a new product. Completes once Firestore has it queued — at once,
  /// online or not.
  Future<Product> add(ProductDraft draft) async {
    final product = draft.toProduct(remote.newId());
    await remote.send(ProductOp.create(product));
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
    await remote.send(
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
    await remote.send(
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
  /// its quantity. Returns the sale as recorded.
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
    await remote.send(ProductOp.sale(sale));
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
    final current = _latest(original);
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
    await remote.send(ProductOp.editSale(edited, restock));
    return edited;
  }

  /// Refunds [sale]: marks it void and returns its items to stock. A sale
  /// already voided — here or on another phone — is left as it is. Returns
  /// the voided sale.
  Future<Sale> voidSale(Sale sale) async {
    final current = _latest(sale);
    if (current.voided) return current;
    final voided = current.voidedOn(DateTime.now());
    await remote.send(ProductOp.voidSale(voided));
    return voided;
  }

  Future<void> delete(String productId) =>
      remote.send(ProductOp.delete(productId));

  Future<void> dispose() async {
    await _productsSub?.cancel();
    await _salesSub?.cancel();
    await _changes.close();
    await _salesChanges.close();
    await _syncChanges.close();
  }

  /// [sale] as the live list has it now — another phone may have refunded
  /// or edited it since the screen showed it.
  Sale _latest(Sale sale) =>
      _sales?.where((s) => s.id == sale.id).firstOrNull ?? sale;

  void _onProducts(RemoteSnapshot<List<Product>> snapshot) {
    _productSnapshot = snapshot;
    _products = List.unmodifiable(
      [...snapshot.data]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    );
    if (!_changes.isClosed) _changes.add(_products!);
    _publishSync();
  }

  void _onSales(RemoteSnapshot<List<Sale>> snapshot) {
    _saleSnapshot = snapshot;
    _sales = List.unmodifiable(
      [...snapshot.data]
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt)),
    );
    if (!_salesChanges.isClosed) _salesChanges.add(_sales!);
    _publishSync();
    if (!_firstSales.isCompleted) _firstSales.complete();
  }

  void _onSalesError(Object error, StackTrace stack) {
    if (!_salesChanges.isClosed) _salesChanges.addError(error, stack);
    if (!_firstSales.isCompleted) _firstSales.complete();
  }

  void _publishSync() {
    final status = syncStatus;
    if (status == null) return;
    if (status.isSynced) _lastSyncedAt = DateTime.now();
    if (!_syncChanges.isClosed) _syncChanges.add(syncStatus!);
  }

  /// The latest [value] straight away, if there is one, then every change.
  static Stream<T> _replay<T>(StreamController<T> changes, T? value) {
    return Stream.multi((listener) {
      // Subscribing and replaying synchronously leaves no gap for a change
      // to slip between the two.
      if (value != null) listener.add(value);
      final sub = changes.stream.listen(
        listener.add,
        onError: listener.addError,
      );
      listener.onCancel = sub.cancel;
    });
  }

  /// The key older versions of the app kept their own copy of the store
  /// under, with a queue of changes not yet handed to Firestore.
  String get _legacyKey => 'products.v1.$storeId';

  /// Hands any changes the old on-device copy never got to send over to
  /// Firestore, once, then deletes that copy.
  ///
  /// A sale, refund or edit Firestore already shows is skipped: resending
  /// it would move stock twice.
  Future<void> _sendLeftoverOps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyKey);
    if (raw == null) return;

    final ops = <ProductOp>[];
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      for (final op in (json['ops'] as List<dynamic>? ?? const [])) {
        ops.add(ProductOp.fromJson(Map<String, dynamic>.from(op as Map)));
      }
    } on Object {
      // Unreadable: nothing can be recovered from it.
    }

    if (ops.isNotEmpty) {
      await _firstSales.future;
      final known = {for (final s in _sales ?? const <Sale>[]) s.id: s};
      for (final op in ops) {
        final landed = known[op.productId];
        final skip = switch (op.kind) {
          ProductOpKind.sale => landed != null,
          ProductOpKind.voidSale => landed?.voided ?? false,
          ProductOpKind.editSale =>
            landed?.editedAt != null &&
                !landed!.editedAt!.isBefore(op.sale!.editedAt!),
          _ => false,
        };
        if (!skip) await remote.send(op);
      }
    }
    await prefs.remove(_legacyKey);
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
