import 'dart:async';

import 'package:tinda_track/services/product_service.dart';

/// An in-memory stand-in for a store's Firestore `products` and `sales`,
/// behaving the way Firestore does for this app:
/// - listeners get the current data at once, then every change;
/// - a write shows in the listeners straight away;
/// - [offline]: writes queue on the "phone" instead of reaching [server],
///   show as pending, and are delivered in order when back online.
class FakeProductRemote implements ProductRemote {
  FakeProductRemote([List<Product> products = const []])
    : server = {for (final p in products) p.id: p};

  /// What the "server" holds, by id. Changing it directly is another phone
  /// making a change; call [push] so listeners hear of it.
  final Map<String, Product> server;

  /// Sales the server holds, by id.
  final sales = <String, Sale>{};

  /// Every op the server received, in order.
  final sent = <ProductOp>[];

  /// Ops written while offline, waiting for the connection.
  final queued = <ProductOp>[];

  var _nextId = 0;
  var _offline = false;
  final _changes = StreamController<void>.broadcast();

  bool get offline => _offline;

  /// Going online delivers the queue, in order, as Firestore does.
  set offline(bool value) {
    _offline = value;
    if (!value) {
      queued.forEach(_deliver);
      queued.clear();
    }
    push();
  }

  /// Tells listeners the data changed — after a change made "elsewhere".
  void push() => _changes.add(null);

  @override
  String newId() => 'new-${_nextId++}';

  @override
  Stream<RemoteSnapshot<List<Product>>> watchProducts() =>
      _live(_productSnapshot);

  @override
  Stream<RemoteSnapshot<List<Sale>>> watchSales({required DateTime since}) =>
      _live(() => _saleSnapshot(since));

  @override
  Future<void> send(ProductOp op) async {
    if (_offline) {
      queued.add(op);
    } else {
      _deliver(op);
    }
    push();
  }

  Stream<T> _live<T>(T Function() snapshot) => Stream.multi((listener) {
    listener.add(snapshot());
    final sub = _changes.stream.listen((_) => listener.add(snapshot()));
    listener.onCancel = sub.cancel;
  });

  void _deliver(ProductOp op) {
    // An update to a product deleted elsewhere fails on the server, as a
    // Firestore `update` of a missing document does.
    if (op.kind == ProductOpKind.update && !server.containsKey(op.productId)) {
      return;
    }
    sent.add(op);
    if (op.sale != null) sales[op.sale!.id] = op.sale!;
    final applied = op.applyTo(server.values.toList());
    server
      ..clear()
      ..addAll({for (final p in applied) p.id: p});
  }

  /// The server's products with queued writes on top, as the phone shows
  /// them offline.
  RemoteSnapshot<List<Product>> _productSnapshot() {
    var products = server.values.toList();
    for (final op in queued) {
      products = op.applyTo(products);
    }
    final ids = {for (final p in products) p.id};
    return RemoteSnapshot(
      products,
      pendingIds: {
        for (final op in queued)
          for (final id in _productsTouched(op))
            if (ids.contains(id)) id,
      },
      fromCache: _offline,
    );
  }

  RemoteSnapshot<List<Sale>> _saleSnapshot(DateTime since) {
    final local = {...sales};
    for (final op in queued) {
      if (op.sale != null) local[op.sale!.id] = op.sale!;
    }
    return RemoteSnapshot(
      [
        for (final s in local.values)
          if (!s.completedAt.isBefore(since)) s,
      ],
      pendingIds: {
        for (final op in queued)
          if (op.sale != null) op.sale!.id,
      },
      fromCache: _offline,
    );
  }

  static Iterable<String> _productsTouched(ProductOp op) => switch (op.kind) {
    ProductOpKind.create ||
    ProductOpKind.update ||
    ProductOpKind.delete => [op.productId],
    ProductOpKind.sale || ProductOpKind.voidSale => op.sale!.soldByProduct.keys,
    ProductOpKind.editSale => op.fields.keys,
  };
}
