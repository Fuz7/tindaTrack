import 'dart:convert';

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

const _owner = Cashier.owner('owner-uid');

ProductRepository _repo(ProductRemote remote) =>
    ProductRepository(storeId: 'store-1', remote: remote);

/// Lets listeners deliver.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// A repository listening to [remote], with its first answers in.
Future<ProductRepository> _loaded(FakeProductRemote remote) async {
  final repo = _repo(remote);
  await repo.load();
  await _settle();
  return repo;
}

List<String> _names(List<Product> products) => [
  for (final p in products) p.name,
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('live from Firestore', () {
    test('shows the catalog, sorted by name', () async {
      final repo = await _loaded(
        FakeProductRemote([
          _coke,
          const Product(id: 'a', name: 'Alaska', stock: 1, sellCentavos: 1),
        ]),
      );
      expect(_names(await repo.watch().first), ['Alaska', 'Coke Mismo']);
    });

    test("another phone's change shows by itself", () async {
      final remote = FakeProductRemote([_coke]);
      final repo = await _loaded(remote);
      final seen = <List<String>>[];
      final sub = repo.watch().listen((p) => seen.add(_names(p)));

      remote.server['tide'] = const Product(
        id: 'tide',
        name: 'Tide Bar',
        stock: 9,
        sellCentavos: 1500,
      );
      remote.push();
      await _settle();
      await sub.cancel();

      expect(seen.last, ['Coke Mismo', 'Tide Bar']);
    });

    test("another phone's sale shows in the history", () async {
      final remote = FakeProductRemote([_coke]);
      final repo = await _loaded(remote);

      remote.sales['other'] = Sale(
        id: 'other',
        items: const [
          SaleItem(
            productId: 'coke',
            name: 'Coke',
            unitCentavos: 2000,
            quantity: 1,
          ),
        ],
        receivedCentavos: 2000,
        completedAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      remote.push();
      await _settle();

      expect([for (final s in await repo.watchSales().first) s.id], ['other']);
    });

    test('a new product reaches the server and shows at once', () async {
      final remote = FakeProductRemote([_coke]);
      final repo = await _loaded(remote);

      final product = await repo.add(_draft);
      await _settle();

      expect(remote.server[product.id]!.name, 'San Miguel');
      expect(_names(await repo.watch().first), ['Coke Mismo', 'San Miguel']);
    });
  });

  group('offline', () {
    test('a change shows at once, waits, and sends when back', () async {
      final remote = FakeProductRemote([_coke]);
      final repo = await _loaded(remote);
      remote.offline = true;
      await _settle();

      final product = await repo.add(_draft);
      await _settle();

      expect(_names(await repo.watch().first), ['Coke Mismo', 'San Miguel']);
      expect(remote.server.containsKey(product.id), isFalse);
      expect(remote.queued, hasLength(1));

      remote.offline = false;
      await _settle();
      expect(remote.server[product.id]!.name, 'San Miguel');
      expect(remote.queued, isEmpty);
    });

    test('queued changes go in the order they were made', () async {
      final remote = FakeProductRemote([_coke]);
      final repo = await _loaded(remote);
      remote.offline = true;

      final added = await repo.add(_draft);
      await repo.delete('coke');
      await _settle();
      expect(_names(await repo.watch().first), ['San Miguel']);

      remote.offline = false;
      await _settle();
      expect(
        [for (final op in remote.sent) op.kind],
        [ProductOpKind.create, ProductOpKind.delete],
      );
      expect(remote.server.keys, [added.id]);
    });
  });

  group('sync status', () {
    Future<SyncStatus> statusOf(ProductRepository repo) async {
      await _settle();
      return repo.syncStatus!;
    }

    test('online with nothing waiting is synced', () async {
      final repo = await _loaded(FakeProductRemote([_coke]));
      final status = await statusOf(repo);
      expect(status.online, isTrue);
      expect(status.pending, 0);
      expect(status.isSynced, isTrue);
      expect(status.lastSyncedAt, isNotNull);
    });

    test('offline, counts what is waiting; synced again once sent', () async {
      final remote = FakeProductRemote([_coke]);
      final repo = await _loaded(remote);
      remote.offline = true;

      await repo.recordSale(
        items: const [
          SaleItem(
            productId: 'coke',
            name: 'Coke',
            unitCentavos: 2000,
            quantity: 2,
          ),
        ],
        receivedCentavos: 4000,
        cashier: _owner,
      );
      var status = await statusOf(repo);
      expect(status.online, isFalse);
      // The receipt, and Coke's stock.
      expect(status.pending, 2);
      expect(status.isSynced, isFalse);

      remote.offline = false;
      status = await statusOf(repo);
      expect(status.pending, 0);
      expect(status.isSynced, isTrue);
    });

    test('offline with nothing waiting says offline, not synced', () async {
      final remote = FakeProductRemote([_coke]);
      final repo = await _loaded(remote);
      remote.offline = true;

      final status = await statusOf(repo);
      expect(status.online, isFalse);
      expect(status.pending, 0);
      expect(status.isSynced, isFalse);
    });

    test('is unknown until both lists have answered', () {
      final repo = _repo(FakeProductRemote([_coke]));
      expect(repo.syncStatus, isNull);
    });
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
      final repo = await _loaded(remote);

      await repo.update(coke, edited(sell: 2500, stock: 7, alerts: false));
      await _settle();

      final op = remote.sent.single;
      expect(op.kind, ProductOpKind.update);
      expect(op.fields, {'sellCentavos': 2500, 'stockAlerts': false});
      expect(op.stockDelta, -3);
      expect(remote.server['coke']!.stock, 7);
    });

    test('a stock edit combines with a sale made elsewhere', () async {
      final remote = FakeProductRemote([coke]);
      final repo = await _loaded(remote);

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
      final repo = await _loaded(remote);

      await repo.update(coke, edited());
      await _settle();
      expect(remote.sent, isEmpty);
    });

    test('a stock update sends only the difference', () async {
      final remote = FakeProductRemote([coke]);
      final repo = await _loaded(remote);

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
      // Both changes count, here as on the server.
      expect(remote.server['coke']!.stock, 9);
      expect((await repo.watch().first).single.stock, 9);
    });

    test('a stock update leaves a log entry with its reason', () async {
      final remote = FakeProductRemote([coke]);
      final repo = await _loaded(remote);

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
      final remote = FakeProductRemote([coke]);
      final repo = await _loaded(remote);

      expect(() => repo.adjustStock(coke, 7), throwsArgumentError);
      expect(
        () => repo.adjustStock(coke, 7, reason: StockReason.other),
        throwsArgumentError,
      );
      // An increase logs no reason even if one is passed.
      await repo.adjustStock(coke, 12, reason: StockReason.lost);
      expect(remote.sent.single.adjustment!.reason, isNull);
    });

    test('an edit to a product deleted elsewhere does nothing', () async {
      final remote = FakeProductRemote([coke]);
      final repo = await _loaded(remote);
      remote.server.clear();

      await repo.update(coke, edited(stock: 5));
      await _settle();
      expect(remote.server, isEmpty);
      expect(await repo.watch().first, isEmpty);
    });
  });

  group('sales', () {
    const coke = Product(
      id: 'coke',
      name: 'Coke',
      stock: 10,
      sellCentavos: 2000,
    );
    const bread = Product(
      id: 'bread',
      name: 'Bread',
      stock: 5,
      sellCentavos: 6500,
    );
    const items = [
      SaleItem(
        productId: 'coke',
        name: 'Coke',
        unitCentavos: 2000,
        quantity: 3,
      ),
      SaleItem(name: 'Manual Entry', unitCentavos: 1500, quantity: 1),
      SaleItem(
        productId: 'bread',
        name: 'Bread',
        unitCentavos: 6500,
        quantity: 1,
      ),
    ];

    test('a sale takes stock down and is sent', () async {
      final remote = FakeProductRemote([coke, bread]);
      final repo = await _loaded(remote);

      final sale = await repo.recordSale(
        items: items,
        receivedCentavos: 20000,
        cashier: _owner,
      );
      await _settle();

      expect(sale.totalCentavos, 14000);
      expect(sale.changeCentavos, 6000);
      final stock = {for (final p in await repo.watch().first) p.id: p.stock};
      expect(stock, {'coke': 7, 'bread': 4});
      expect(remote.sent.single.kind, ProductOpKind.sale);
      expect(remote.server['coke']!.stock, 7);
    });

    test('an offline sale shows at once and is sent when back', () async {
      final remote = FakeProductRemote([coke, bread]);
      final repo = await _loaded(remote);
      remote.offline = true;

      final sale = await repo.recordSale(
        items: items,
        receivedCentavos: 14000,
        cashier: _owner,
      );
      await _settle();
      expect((await repo.watchSales().first).single.id, sale.id);
      expect(
        (await repo.watch().first).firstWhere((p) => p.id == 'bread').stock,
        4,
      );
      expect(remote.server['bread']!.stock, 5);

      remote.offline = false;
      await _settle();
      expect(remote.server['bread']!.stock, 4);
      expect(remote.sales.containsKey(sale.id), isTrue);
    });

    test('two phones selling the same product both count', () async {
      final remote = FakeProductRemote([coke]);
      final repo = await _loaded(remote);
      remote.offline = true;

      await repo.recordSale(
        items: const [
          SaleItem(
            productId: 'coke',
            name: 'Coke',
            unitCentavos: 2000,
            quantity: 2,
          ),
        ],
        receivedCentavos: 4000,
        cashier: _owner,
      );
      // Meanwhile, online, another phone sells 3.
      remote.server['coke'] = Product.fromMap('coke', {
        ...coke.toMap(),
        'stock': 7,
      });

      remote.offline = false;
      await _settle();
      expect(remote.server['coke']!.stock, 5);
      expect((await repo.watch().first).single.stock, 5);
    });

    test('too little cash or no items is refused', () async {
      final repo = await _loaded(FakeProductRemote([coke]));
      expect(
        () => repo.recordSale(
          items: items,
          receivedCentavos: 100,
          cashier: _owner,
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.recordSale(
          items: const [],
          receivedCentavos: 0,
          cashier: _owner,
        ),
        throwsArgumentError,
      );
    });
  });

  group('sales history', () {
    const coke = Product(
      id: 'coke',
      name: 'Coke',
      stock: 10,
      sellCentavos: 2000,
    );
    const items = [
      SaleItem(
        productId: 'coke',
        name: 'Coke',
        unitCentavos: 2000,
        quantity: 3,
      ),
    ];

    test('newest first', () async {
      final remote = FakeProductRemote([coke]);
      final repo = await _loaded(remote);
      final first = await repo.recordSale(
        items: items,
        receivedCentavos: 6000,
        cashier: _owner,
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final second = await repo.recordSale(
        items: items,
        receivedCentavos: 6000,
        cashier: _owner,
      );
      await _settle();

      expect(
        [for (final s in await repo.watchSales().first) s.id],
        [second.id, first.id],
      );
    });

    test('only the last 60 days are listened to', () async {
      final remote = FakeProductRemote([coke]);
      Sale at(String id, Duration ago) => Sale(
        id: id,
        items: items,
        receivedCentavos: 6000,
        completedAt: DateTime.now().subtract(ago),
      );
      remote.sales['recent'] = at('recent', const Duration(days: 59));
      remote.sales['old'] = at('old', const Duration(days: 61));
      final repo = await _loaded(remote);

      expect([for (final s in await repo.watchSales().first) s.id], ['recent']);
    });

    test('a refund voids the sale and restocks, once', () async {
      final remote = FakeProductRemote([coke]);
      final repo = await _loaded(remote);
      final sale = await repo.recordSale(
        items: items,
        receivedCentavos: 6000,
        cashier: _owner,
      );
      await _settle();
      expect(remote.server['coke']!.stock, 7);

      final voided = await repo.voidSale(sale);
      await _settle();
      await repo.voidSale(sale); // again: no second restock
      await _settle();

      expect(voided.voided, isTrue);
      expect((await repo.watchSales().first).single.voided, isTrue);
      expect((await repo.watch().first).single.stock, 10);
      expect(remote.server['coke']!.stock, 10);
      expect(remote.sales[sale.id]!.voided, isTrue);
    });

    test('a sale refunded on another phone is not refunded again', () async {
      final remote = FakeProductRemote([coke]);
      final repo = await _loaded(remote);
      final sale = await repo.recordSale(
        items: items,
        receivedCentavos: 6000,
        cashier: _owner,
      );
      await _settle();

      // Another phone refunds it; this screen still shows it standing.
      await remote.send(ProductOp.voidSale(sale.voidedOn(DateTime.now())));
      await _settle();
      final before = remote.sent.length;

      await repo.voidSale(sale);
      await _settle();
      expect(remote.sent.length, before);
      expect(remote.server['coke']!.stock, 10);
    });
  });

  group('sale edits', () {
    const coke = Product(
      id: 'coke',
      name: 'Coke',
      stock: 10,
      sellCentavos: 2000,
    );
    const bread = Product(
      id: 'bread',
      name: 'Bread',
      stock: 5,
      sellCentavos: 6500,
    );
    SaleItem line(String id, String name, int unit, int qty) =>
        SaleItem(productId: id, name: name, unitCentavos: unit, quantity: qty);

    Future<(FakeProductRemote, ProductRepository, Sale)> setUpSale() async {
      final remote = FakeProductRemote([coke, bread]);
      final repo = await _loaded(remote);
      final sale = await repo.recordSale(
        items: [line('coke', 'Coke', 2000, 3), line('bread', 'Bread', 6500, 1)],
        receivedCentavos: 20000,
        cashier: _owner,
      );
      await _settle();
      return (remote, repo, sale);
    }

    test('a sale records who rang it up', () async {
      final (_, repo, sale) = await setUpSale();
      expect(sale.cashierName, 'Owner');
      expect(sale.cashierUid, 'owner-uid');
      expect((await repo.watchSales().first).single.cashierName, 'Owner');
    });

    test('quantity changes move stock by the difference only', () async {
      final (remote, repo, sale) = await setUpSale();
      // After the sale: coke 7, bread 4.

      final edited = await repo.editSale(
        sale,
        // Coke 3 → 1 (two back), bread removed (one back).
        items: [line('coke', 'Coke', 2000, 1)],
        receivedCentavos: 5000,
        customerName: '  Aling Nena ',
        editor: _owner,
      );
      await _settle();

      expect(edited.totalCentavos, 2000);
      expect(edited.customerName, 'Aling Nena');
      expect(edited.editedBy, 'Owner');
      expect(edited.cashierName, 'Owner'); // who rang it up is kept
      final stock = {for (final p in await repo.watch().first) p.id: p.stock};
      expect(stock, {'coke': 9, 'bread': 5});
      expect(remote.server['coke']!.stock, 9);
      expect(remote.sales[sale.id]!.customerName, 'Aling Nena');
    });

    test('raising a quantity takes more stock', () async {
      final (_, repo, sale) = await setUpSale();
      await repo.editSale(
        sale,
        items: [line('coke', 'Coke', 2000, 5), line('bread', 'Bread', 6500, 1)],
        receivedCentavos: 20000,
        customerName: null,
        editor: _owner,
      );
      await _settle();
      expect(
        (await repo.watch().first).firstWhere((p) => p.id == 'coke').stock,
        5,
      );
    });

    test('an unchanged edit sends nothing', () async {
      final (remote, repo, sale) = await setUpSale();
      final before = remote.sent.length;
      final result = await repo.editSale(
        sale,
        items: sale.items,
        receivedCentavos: sale.receivedCentavos,
        customerName: '',
        editor: _owner,
      );
      expect(result.editedAt, isNull);
      expect(remote.sent.length, before);
    });

    test('a refunded sale, or one with no items, cannot be edited', () async {
      final (_, repo, sale) = await setUpSale();
      expect(
        () => repo.editSale(
          sale,
          items: const [],
          receivedCentavos: 0,
          customerName: null,
          editor: _owner,
        ),
        throwsArgumentError,
      );
      await repo.voidSale(sale);
      await _settle();
      expect(
        () => repo.editSale(
          sale,
          items: [line('coke', 'Coke', 2000, 1)],
          receivedCentavos: 5000,
          customerName: null,
          editor: _owner,
        ),
        throwsStateError,
      );
    });

    test('linking a manual entry to a product takes its stock', () async {
      final remote = FakeProductRemote([coke, bread]);
      final repo = await _loaded(remote);
      const manual = SaleItem(
        name: 'Manual Entry',
        unitCentavos: 6500,
        quantity: 1,
      );
      final sale = await repo.recordSale(
        items: const [manual],
        receivedCentavos: 6500,
        cashier: _owner,
      );
      await _settle();
      expect(remote.server['bread']!.stock, 5); // a manual entry moves none

      await repo.editSale(
        sale,
        items: [line('bread', 'Bread', 6500, 1)],
        receivedCentavos: 6500,
        customerName: null,
        editor: _owner,
      );
      await _settle();

      expect(
        (await repo.watch().first).firstWhere((p) => p.id == 'bread').stock,
        4,
      );
      expect(remote.server['bread']!.stock, 4);
    });
  });

  group('the old on-device copy', () {
    const coke = Product(
      id: 'coke',
      name: 'Coke',
      stock: 10,
      sellCentavos: 2000,
    );
    Sale sale(String id) => Sale(
      id: id,
      items: const [
        SaleItem(
          productId: 'coke',
          name: 'Coke',
          unitCentavos: 2000,
          quantity: 2,
        ),
      ],
      receivedCentavos: 4000,
      completedAt: DateTime.now(),
    );

    void leaveOldCopy(List<ProductOp> ops) {
      SharedPreferences.setMockInitialValues({
        'products.v1.store-1': jsonEncode({
          'products': const [],
          'ops': [for (final op in ops) op.toJson()],
        }),
      });
    }

    test('its unsent changes are sent once, then it is deleted', () async {
      final unsent = sale('never-sent');
      leaveOldCopy([ProductOp.sale(unsent)]);
      final remote = FakeProductRemote([coke]);

      await _loaded(remote);
      await _settle();

      expect(remote.sales.containsKey('never-sent'), isTrue);
      expect(remote.server['coke']!.stock, 8);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('products.v1.store-1'), isNull);
    });

    test('a sale Firestore already has is not sent twice', () async {
      final landed = sale('landed');
      leaveOldCopy([ProductOp.sale(landed)]);
      final remote = FakeProductRemote([coke]);
      await remote.send(ProductOp.sale(landed)); // stock 10 → 8
      final before = remote.sent.length;

      await _loaded(remote);
      await _settle();

      expect(remote.sent.length, before);
      expect(remote.server['coke']!.stock, 8); // not 6
    });
  });
}
