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
  final saves = <String>[];

  @override
  String newId() => 'new-${_nextId++}';

  @override
  Future<List<Product>> fetchAll() async {
    if (offline) throw StateError('offline');
    return server.values.toList();
  }

  @override
  Future<void> save(Product product) async {
    if (offline) throw StateError('offline');
    saves.add(product.id);
    server[product.id] = product;
  }
}
