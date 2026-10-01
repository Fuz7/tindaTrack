import 'package:flutter_test/flutter_test.dart';
import 'package:tinda_track/services/product_service.dart';
import 'package:tinda_track/services/sales_insights.dart';

// Thursday 1 October 2026, mid-afternoon.
final _now = DateTime(2026, 10, 1, 15);

const _coke = Product(
  id: 'coke',
  name: 'Coke Mismo',
  stock: 20,
  sellCentavos: 2000,
  buyCentavos: 1500,
);
const _canton = Product(
  id: 'canton',
  name: 'Pancit Canton',
  stock: 3,
  sellCentavos: 1800,
  buyCentavos: 1400,
);
const _soap = Product(
  id: 'soap',
  name: 'Safeguard',
  stock: 0,
  sellCentavos: 4500,
); // no buy price
const _rare = Product(
  id: 'rare',
  name: 'Candles',
  stock: 1,
  sellCentavos: 1000,
  stockAlerts: false,
);

Sale _sale(
  String id,
  DateTime at,
  List<SaleItem> items, {
  bool voided = false,
}) => Sale(
  id: id,
  items: items,
  receivedCentavos: 100000,
  completedAt: at,
  voidedAt: voided ? at : null,
);

SaleItem _item(Product p, int qty) => SaleItem(
  productId: p.id,
  name: p.name,
  unitCentavos: p.sellCentavos,
  quantity: qty,
);

SalesInsights _compute(List<Sale> sales, RangePreset preset) =>
    _computeRange(sales, InsightsRange.preset(preset, _now));

SalesInsights _computeRange(List<Sale> sales, InsightsRange range) =>
    SalesInsights.compute(
      sales: sales,
      products: const [_coke, _canton, _soap, _rare],
      range: range,
      lowStockThreshold: 5,
      now: _now,
    );

void main() {
  group('ranges', () {
    test('presets end today; Last Month is the last 30 days', () {
      final month = InsightsRange.preset(RangePreset.month, _now);
      expect(month.label, 'Last Month');
      expect(month.firstDay, DateTime(2026, 9, 2));
      expect(month.lastDay, DateTime(2026, 10, 1));
      expect(month.days, 30);
      expect(month.dates, 'Sep 2 – Oct 1');

      final today = InsightsRange.preset(RangePreset.today, _now);
      expect(today.days, 1);
      expect(today.dates, 'Oct 1');
    });

    test('a custom range is labelled by its dates', () {
      final range = InsightsRange.custom(
        DateTime(2026, 9, 3, 18),
        DateTime(2026, 9, 18),
      );
      expect(range.firstDay, DateTime(2026, 9, 3));
      expect(range.days, 16);
      expect(range.label, 'Sep 3 – Sep 18');
    });

    test('a custom range counts whole days, to the end of its last', () {
      final insights = _computeRange([
        _sale('in-first', DateTime(2026, 9, 10, 0, 5), [_item(_coke, 1)]),
        _sale('in-last', DateTime(2026, 9, 12, 23, 59), [_item(_coke, 1)]),
        _sale('before', DateTime(2026, 9, 9, 23, 59), [_item(_coke, 1)]),
        _sale('after', DateTime(2026, 9, 13, 0, 1), [_item(_coke, 1)]),
        // The 3 days before (7–9 Sep) are the comparison.
        _sale('prev', DateTime(2026, 9, 8, 12), [_item(_coke, 4)]),
      ], InsightsRange.custom(DateTime(2026, 9, 10), DateTime(2026, 9, 12)));

      expect(insights.transactions, 2);
      expect(insights.salesCentavos, 4000);
      expect(insights.previousSalesCentavos, 2000 + 8000);
      expect(insights.salesChange, closeTo(-0.6, 1e-9));
    });

    test('no comparison when the stretch before is past the history', () {
      // 40 days from 1 Sep: the 40 before reach back past 60 days.
      final insights = _computeRange([
        _sale('a', DateTime(2026, 9, 5), [_item(_coke, 1)]),
      ], InsightsRange.custom(DateTime(2026, 8, 23), DateTime(2026, 10, 1)));

      expect(insights.previousSalesCentavos, isNull);
      expect(insights.salesChange, isNull);
    });
  });

  test('totals the period, leaving refunds out', () {
    final insights = _compute([
      _sale('a', DateTime(2026, 10, 1, 9), [_item(_coke, 2)]),
      _sale('b', DateTime(2026, 9, 28, 9), [_item(_canton, 1)]),
      _sale('void', DateTime(2026, 10, 1, 10), [
        _item(_coke, 10),
      ], voided: true),
      // Before the 7-day window (25 Sep is day 1 of it).
      _sale('old', DateTime(2026, 9, 24, 23), [_item(_coke, 5)]),
    ], RangePreset.week);

    expect(insights.salesCentavos, 4000 + 1800);
    expect(insights.transactions, 2);
  });

  test('profit uses buy prices, and says when some are missing', () {
    final insights = _compute([
      _sale('a', DateTime(2026, 10, 1, 9), [
        _item(_coke, 2), // (20 - 15) × 2 = 10.00
        _item(_soap, 1), // no buy price: left out
        const SaleItem(name: 'Manual Entry', unitCentavos: 500, quantity: 1),
      ]),
    ], RangePreset.today);

    expect(insights.profitCentavos, 1000);
    expect(insights.profitIsPartial, isTrue);
  });

  test('compares with the same stretch of the period before', () {
    final insights = _compute([
      _sale('today', DateTime(2026, 10, 1, 9), [_item(_coke, 3)]),
      // Yesterday before 3 pm counts; after 3 pm is past "now" yesterday.
      _sale('yday-am', DateTime(2026, 9, 30, 10), [_item(_coke, 2)]),
      _sale('yday-pm', DateTime(2026, 9, 30, 20), [_item(_coke, 50)]),
    ], RangePreset.today);

    expect(insights.salesCentavos, 6000);
    expect(insights.previousSalesCentavos, 4000);
    expect(insights.salesChange, closeTo(0.5, 1e-9));
  });

  test('no earlier sales means no change to show', () {
    final insights = _compute([
      _sale('a', DateTime(2026, 10, 1, 9), [_item(_coke, 1)]),
    ], RangePreset.month);

    expect(insights.salesChange, isNull);
    expect(insights.profitChange, isNull);
  });

  group('sales trend', () {
    test('a week is one bar per day, labelled by weekday', () {
      final insights = _compute([
        _sale('a', DateTime(2026, 10, 1, 9), [_item(_coke, 1)]),
        _sale('b', DateTime(2026, 10, 1, 11), [_item(_coke, 1)]),
        _sale('c', DateTime(2026, 9, 25, 8), [_item(_canton, 1)]),
      ], RangePreset.week);

      final bars = insights.trend;
      expect(insights.trendUnit, TrendUnit.day);
      expect(bars, hasLength(7));
      expect(bars.first.start, DateTime(2026, 9, 25));
      expect(bars.first.axisLabel, 'FRI');
      expect(bars.first.title, 'Friday, Sep 25');
      expect(bars.first.totalCentavos, 1800);
      expect(bars.last.totalCentavos, 4000);
      expect(bars[3].totalCentavos, 0);
    });

    test('today is one bar per hour, 6 AM to 10 PM', () {
      final insights = _compute([
        _sale('a', DateTime(2026, 10, 1, 9, 30), [_item(_coke, 1)]),
        _sale('b', DateTime(2026, 10, 1, 9, 45), [_item(_coke, 2)]),
      ], RangePreset.today);

      final bars = insights.trend;
      expect(insights.trendUnit, TrendUnit.hour);
      expect(bars, hasLength(16));
      expect(bars.first.title, '6 AM – 7 AM');
      expect(bars.last.title, '9 PM – 10 PM');
      final nine = bars.firstWhere((b) => b.start.hour == 9);
      expect(nine.totalCentavos, 6000);
      expect(nine.axisLabel, '9a');
      // Only every third hour is labelled.
      expect([for (final b in bars) b.axisLabel].nonNulls, [
        '6a',
        '9a',
        '12p',
        '3p',
        '6p',
        '9p',
      ]);
    });

    test('an hourly chart widens for a sale outside 6 AM – 10 PM', () {
      final insights = _computeRange([
        _sale('late', DateTime(2026, 9, 30, 23, 15), [_item(_coke, 1)]),
      ], InsightsRange.custom(DateTime(2026, 9, 30), DateTime(2026, 9, 30)));

      expect(insights.trend.last.title, '11 PM – 12 AM');
      expect(insights.trend.last.totalCentavos, 2000);
    });

    test('8 to 14 days are daily bars labelled by date', () {
      final insights = _computeRange(
        const [],
        InsightsRange.custom(DateTime(2026, 9, 18), DateTime(2026, 10, 1)),
      );

      expect(insights.trendUnit, TrendUnit.day);
      expect(insights.trend, hasLength(14));
      expect(insights.trend.first.axisLabel, '18');
    });

    test('longer ranges are weekly bars; a short last week says so', () {
      final insights = _compute([
        _sale('w1', DateTime(2026, 9, 3, 10), [_item(_coke, 1)]),
        _sale('w5', DateTime(2026, 10, 1, 10), [_item(_coke, 2)]),
      ], RangePreset.month); // Sep 2 – Oct 1: 4 weeks and 2 days

      final bars = insights.trend;
      expect(insights.trendUnit, TrendUnit.week);
      expect(bars, hasLength(5));
      expect(bars.first.title, 'Sep 2 – 8');
      expect(bars.first.axisLabel, 'Sep 2');
      expect(bars.first.totalCentavos, 2000);
      expect(bars.last.title, 'Sep 30 – Oct 1 (2 days)');
      expect(bars.last.totalCentavos, 4000);
    });
  });

  test('chart scale: round steps, top at or above the peak', () {
    expect(chartScale(0), (max: 10000, step: 3333));
    // ₱487 peak → ₱200 steps up to ₱600.
    expect(chartScale(48700), (max: 60000, step: 20000));
    // ₱1,234 → ₱500 steps up to ₱1.5K.
    expect(chartScale(123400), (max: 150000, step: 50000));
    // Exactly on a step stays there.
    expect(chartScale(300000), (max: 300000, step: 100000));
  });

  test('best sellers rank by revenue, top five, products only', () {
    final insights = _compute([
      _sale('a', DateTime(2026, 9, 30), [
        _item(_canton, 10), // 180.00
        _item(_coke, 5), // 100.00
        const SaleItem(name: 'Manual Entry', unitCentavos: 99900, quantity: 1),
      ]),
      _sale('b', DateTime(2026, 9, 29), [_item(_coke, 5)]), // coke 200.00
    ], RangePreset.week);

    expect(
      [for (final s in insights.bestSellers) s.productId],
      ['coke', 'canton'],
    );
    expect(insights.bestSellers.first.units, 10);
    expect(insights.bestSellers.first.revenueCentavos, 20000);
  });

  test('low stock: low and out, emptiest first, alerts respected', () {
    final insights = _compute(const [], RangePreset.week);

    // Candles is at 1 but has stock alerts off.
    expect([for (final p in insights.lowStock) p.id], ['soap', 'canton']);
  });

  test('compact peso amounts', () {
    expect(formatCompactPeso(95050), '₱950.50');
    expect(formatCompactPeso(123456), '₱1.2K');
    expect(formatCompactPeso(14250000), '₱142.5K');
    expect(formatCompactPeso(200000), '₱2K');
    expect(formatCompactPeso(130000000), '₱1.3M');
    expect(formatCompactPeso(99996000), '₱1M'); // not ₱1000K
    expect(formatCompactPeso(-123456), '-₱1.2K');
    expect(formatCompactPeso(0), '₱0.00');
  });
}
