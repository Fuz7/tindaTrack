import 'dart:async';

import 'package:tinda_track/services/product_service.dart';

/// An in-memory stand-in for Firestore's `products` collection.
class FakeProductRemote implements ProductRemote {
  FakeProductRemote([List<Product> products = const []])
    : server = {for (final p in products) p.id: p};

  /// What the "server" holds, by id.
  final Map<String, Product> server;

  /// While set, every call fails as if offline.
  bool offline = false;

  var _nextId = 0;

  /// Every op the server accepted, in order.
  final sent = <ProductOp>[];

  /// Sales the server holds, by id.
  final sales = <String, Sale>{};

  @override
  String newId() => 'new-${_nextId++}';

  @override
  Future<List<Product>> fetchAll() async {
    if (offline) throw StateError('offline');
    return server.values.toList();
  }

  @override
  Future<List<Sale>> fetchSales({required DateTime since}) async {
    if (offline) throw StateError('offline');
    return [
      for (final s in sales.values)
        if (!s.completedAt.isBefore(since)) s,
    ];
  }

  @override
  Future<void> send(ProductOp op) async {
    if (offline) throw StateError('offline');
    if (op.kind == ProductOpKind.update && !server.containsKey(op.productId)) {
      throw ProductMissing(op.productId);
    }
    sent.add(op);
    if (op.sale != null) sales[op.sale!.id] = op.sale!;
    final applied = op.applyTo(server.values.toList());
    server
      ..clear()
      ..addAll({for (final p in applied) p.id: p});
  }
}
