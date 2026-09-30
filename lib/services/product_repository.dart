import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'product_service.dart';

/// A store's product catalog, kept on the device.
///
/// The app reads products from here, never live from Firestore: search and
/// the Inventory tab work the same with or without a connection. The copy is
/// saved to `SharedPreferences` as one JSON document per store.
///
/// Talking to the server is kept deliberately thin until the real offline
/// sync is built:
/// - [load] refreshes the copy from the server once, in the background, so
///   products added on another device (or before this cache existed) appear.
/// - [add] saves locally first and marks the product *pending*; it is pushed
///   to the server straight away and again on each [load] until the server
///   accepts it. [pendingIds] is what a sync layer would pick up from.
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
  final _pending = <String>{};

  /// Pending products with a save to the server in flight.
  final _pushing = <String>{};

  String get _key => 'products.v1.$storeId';

  /// Products saved on this device that the server has not confirmed yet.
  Set<String> get pendingIds => Set.unmodifiable(_pending);

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
  /// it from the server and retries unconfirmed products. Offline, the second
  /// half fails quietly and the device copy stands.
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
        _pending.addAll((json['pending'] as List<dynamic>).cast<String>());
      } on Object {
        // A corrupt copy is rebuilt from the server rather than crashing the
        // till; anything still pending in it is lost with it.
        products.clear();
        _pending.clear();
      }
    }
    _publish(products);

    unawaited(_refreshFromServer());
  }

  /// Saves a new product on the device, then offers it to the server. The
  /// returned future completes once the device copy is written — it does
  /// not wait for, or fail with, the server.
  Future<Product> add(ProductDraft draft) async {
    final product = draft.toProduct(remote.newId());
    _pending.add(product.id);
    _publish([...?_products, product]);
    await _persist();
    unawaited(_push(product));
    return product;
  }

  Future<void> dispose() => _changes.close();

  Future<void> _refreshFromServer() async {
    final List<Product> server;
    try {
      server = await remote.fetchAll();
    } on Object {
      return; // Offline, or refused: keep the device copy.
    }
    if (_changes.isClosed) return;

    final serverIds = {for (final p in server) p.id};
    // The server knowing a pending product means an earlier push landed.
    _pending.removeWhere(serverIds.contains);
    final unconfirmed = [
      for (final p in _products ?? const <Product>[])
        if (_pending.contains(p.id)) p,
    ];
    _publish([...server, ...unconfirmed]);
    await _persist();

    for (final product in unconfirmed) {
      unawaited(_push(product));
    }
  }

  Future<void> _push(Product product) async {
    // A product added while the startup refresh is in flight would otherwise
    // be offered by both [add] and the refresh.
    if (!_pushing.add(product.id)) return;
    try {
      await remote.save(product);
    } on Object {
      return; // Stays pending; the next load tries again.
    } finally {
      _pushing.remove(product.id);
    }
    if (_changes.isClosed || !_pending.remove(product.id)) return;
    await _persist();
  }

  void _publish(List<Product> products) {
    products.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    _products = List.unmodifiable(products);
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
        'pending': _pending.toList(),
      }),
    );
  }
}
