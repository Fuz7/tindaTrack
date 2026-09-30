import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinda_track/services/product_repository.dart';
import 'package:tinda_track/services/product_service.dart';

import 'support/fake_product_remote.dart';

const _coke = Product(
  id: 'coke',
  name: 'Coke Mismo',
  stock: 5,
  sellCentavos: 2000,
);
const _draft = ProductDraft(name: 'San Miguel', sellCentavos: 6000, stock: 24);

ProductRepository _repo(ProductRemote remote) =>
    ProductRepository(storeId: 'store-1', remote: remote);

/// Lets the background refresh and pushes run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

List<String> _names(List<Product> products) => [
  for (final p in products) p.name,
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('pulls the catalog once and keeps it on the device', () async {
    final first = _repo(FakeProductRemote([_coke]));
    await first.load();
    await _settle();
    expect(_names(await first.watch().first), ['Coke Mismo']);

    // Next launch, offline: the device copy still has it.
    final offline = FakeProductRemote()..offline = true;
    final second = _repo(offline);
    await second.load();
    await _settle();
    expect(_names(await second.watch().first), ['Coke Mismo']);
  });

  test('a new product is stored locally even with no connection', () async {
    final remote = FakeProductRemote([_coke]);
    final repo = _repo(remote);
    await repo.load();
    await _settle();
    remote.offline = true;

    final product = await repo.add(_draft);
    await _settle();

    expect(_names(await repo.watch().first), ['Coke Mismo', 'San Miguel']);
    expect(repo.pendingIds, {product.id});
    expect(remote.sent, isEmpty);

    // It survives a restart, still marked pending.
    final restarted = _repo(remote);
    await restarted.load();
    await _settle();
    expect(_names(await restarted.watch().first), ['Coke Mismo', 'San Miguel']);
    expect(restarted.pendingIds, {product.id});
  });

  test('a pending product is pushed once the server is back', () async {
    final remote = FakeProductRemote()..offline = true;
    final repo = _repo(remote);
    await repo.load();
    final product = await repo.add(_draft);
    await _settle();

    remote.offline = false;
    final next = _repo(remote);
    await next.load();
    await _settle();
    await _settle();

    expect(remote.server.keys, contains(product.id));
    expect(next.pendingIds, isEmpty);
  });

  test('online, a new product reaches the server and is confirmed', () async {
    final remote = FakeProductRemote();
    final repo = _repo(remote);
    await repo.load();

    final product = await repo.add(_draft);
    await _settle();

    expect([for (final op in remote.sent) op.productId], [product.id]);
    expect(repo.pendingIds, isEmpty);
  });

  test('watchers see new products as they are added', () async {
    final repo = _repo(FakeProductRemote()..offline = true);
    await repo.load();
    final seen = <List<String>>[];
    final sub = repo.watch().listen((p) => seen.add(_names(p)));
    await _settle();

    await repo.add(_draft);
    await _settle();
    await sub.cancel();

    expect(seen, [
      <String>[],
      ['San Miguel'],
    ]);
  });

  group('edits', () {
    const coke = Product(
      id: 'coke',
      name: 'Coke Mismo',
      stock: 10,
      sellCentavos: 2000,
      categories: ['Drinks'],
    );
    ProductDraft edited({
      String name = 'Coke Mismo',
      int stock = 10,
      int sell = 2000,
      List<String> categories = const ['Drinks'],
      bool alerts = true,
    }) => ProductDraft(
      name: name,
      sellCentavos: sell,
      stock: stock,
      categories: categories,
      stockAlerts: alerts,
    );

    test('only changed fields are sent, stock as a difference', () async {
      final remote = FakeProductRemote([coke]);
      final repo = _repo(remote);
      await repo.load();
      await _settle();

      await repo.update(coke, edited(sell: 2500, stock: 7, alerts: false));
      await _settle();

      final op = remote.sent.single;
      expect(op.kind, ProductOpKind.update);
      expect(op.fields, {'sellCentavos': 2500, 'stockAlerts': false});
      expect(op.stockDelta, -3);
      expect(remote.server['coke']!.stock, 7);
      expect(repo.pendingOps, isEmpty);
    });

    test('a stock edit combines with a sale made elsewhere', () async {
      final remote = FakeProductRemote([coke]);
      final repo = _repo(remote);
      await repo.load();
      await _settle();

      // Another device sells 2 while this one's form is open at 10…
      remote.server['coke'] = Product.fromMap('coke', {
        ...coke.toMap(),
        'stock': 8,
      });
      // …and the owner here adds a delivery of 5 (10 → 15).
      await repo.update(coke, edited(stock: 15));
      await _settle();

      expect(remote.server['coke']!.stock, 13);
    });

    test('an unchanged save sends nothing', () async {
      final remote = FakeProductRemote([coke]);
      final repo = _repo(remote);
      await repo.load();
      await _settle();

      await repo.update(coke, edited());
      await _settle();
      expect(remote.sent, isEmpty);
    });

    test('offline edits apply locally, queue, and send in order', () async {
      final remote = FakeProductRemote([coke]);
      final repo = _repo(remote);
      await repo.load();
      await _settle();
      remote.offline = true;

      await repo.update(coke, edited(name: 'Coke Zero', stock: 12));
      final added = await repo.add(_draft);
      await repo.delete('coke');
      await _settle();

      expect(_names(await repo.watch().first), ['San Miguel']);
      expect(repo.pendingOps.map((op) => op.kind), [
        ProductOpKind.update,
        ProductOpKind.create,
        ProductOpKind.delete,
      ]);

      // After a restart, online again: the queue drains in order.
      remote.offline = false;
      final next = _repo(remote);
      await next.load();
      await _settle();
      await _settle();
      expect(next.pendingOps, isEmpty);
      expect(remote.server.keys, [added.id]);
      expect(_names(await next.watch().first), ['San Miguel']);
    });

    test('a refresh from the server keeps queued edits on top', () async {
      final remote = FakeProductRemote([coke]);
      final seeded = _repo(remote);
      await seeded.load();
      await _settle();
      remote.offline = true;
      await seeded.update(coke, edited(stock: 4));
      await _settle();

      // The server changes meanwhile; the device can fetch but not send.
      remote.server['coke'] = Product.fromMap('coke', {
        ...coke.toMap(),
        'stock': 9,
      });
      expect(seeded.pendingOps, hasLength(1));
      final reloaded = _repo(_FetchOnly(remote));
      await reloaded.load();
      await _settle();

      // 9 on the server, −6 queued here.
      expect((await reloaded.watch().first).single.stock, 3);
    });

    test('a stock update sends only the difference', () async {
      final remote = FakeProductRemote([coke]);
      final repo = _repo(remote);
      await repo.load();
      await _settle();

      // Sold 3 elsewhere (10 → 7) while the owner here counted 12.
      remote.server['coke'] = Product.fromMap('coke', {
        ...coke.toMap(),
        'stock': 7,
      });
      await repo.adjustStock(coke, 12);
      await _settle();

      final op = remote.sent.single;
      expect(op.fields, isEmpty);
      expect(op.stockDelta, 2);
      expect(remote.server['coke']!.stock, 9);
      expect((await repo.watch().first).single.stock, 12);
    });

    test('a stock update leaves a log entry with its reason', () async {
      final remote = FakeProductRemote([coke]);
      final repo = _repo(remote);
      await repo.load();
      await _settle();

      await repo.adjustStock(
        coke,
        7,
        reason: StockReason.expired,
        note: '  past date ',
      );
      await _settle();

      final entry = remote.sent.single.adjustment!;
      expect(entry.productName, 'Coke Mismo');
      expect((entry.before, entry.after, entry.delta), (10, 7, -3));
      expect(entry.reason, StockReason.expired);
      expect(entry.note, 'past date');
    });

    test('a decrease without a reason is refused', () async {
      final repo = _repo(FakeProductRemote([coke]));
      await repo.load();
      await _settle();

      expect(() => repo.adjustStock(coke, 7), throwsArgumentError);
      expect(
        () => repo.adjustStock(coke, 7, reason: StockReason.other),
        throwsArgumentError,
      );
      // An increase logs no reason even if one is passed.
      await repo.adjustStock(coke, 12, reason: StockReason.lost);
      expect(repo.pendingOps.single.adjustment!.reason, isNull);
    });

    test('a queued adjustment survives a restart', () async {
      final remote = FakeProductRemote([coke]);
      final repo = _repo(remote);
      await repo.load();
      await _settle();
      remote.offline = true;
      await repo.adjustStock(coke, 8, reason: StockReason.defective);
      await _settle();

      final restarted = _repo(remote);
      await restarted.load();
      final entry = restarted.pendingOps.single.adjustment!;
      expect(entry.reason, StockReason.defective);
      expect(entry.delta, -2);
    });

    test('an edit to a product deleted elsewhere is dropped', () async {
      final remote = FakeProductRemote([coke]);
      final repo = _repo(remote);
      await repo.load();
      await _settle();
      remote.server.clear();

      await repo.update(coke, edited(stock: 5));
      await _settle();
      expect(repo.pendingOps, isEmpty);
    });
  });
}

/// Reads [inner]'s catalog but can't send — online for fetches only.
class _FetchOnly implements ProductRemote {
  _FetchOnly(this.inner);
  final FakeProductRemote inner;

  @override
  String newId() => inner.newId();

  @override
  Future<List<Product>> fetchAll() async => inner.server.values.toList();

  @override
  Future<void> send(ProductOp op) async => throw StateError('offline');
}
