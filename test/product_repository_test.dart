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

ProductRepository _repo(FakeProductRemote remote) =>
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
    expect(remote.saves, isEmpty);

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

    expect(remote.saves, [product.id]);
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
}
