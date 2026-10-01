import 'product_repository.dart';
import 'product_service.dart';

/// The ready-made ranges in the Analytics period picker, plus [custom].
/// Each preset is whole calendar days ending today, so "Last 7 Days" is today
/// and the six before it, and "Last Month" the last 30 days.
enum RangePreset {
  today('Today', 1),
  week('Last 7 Days', 7),
  month('Last Month', 30),
  custom('Custom Range', 0);

  const RangePreset(this.label, this.days);

  final String label;

  /// Length in days; 0 for [custom], whose length is picked.
  final int days;
}

/// The calendar days the Analytics tab reports on, first to last inclusive.
class InsightsRange {
  const InsightsRange._(this.preset, this.firstDay, this.lastDay);

  /// [preset]'s days as of [now]. Not for [RangePreset.custom].
  factory InsightsRange.preset(RangePreset preset, DateTime now) {
    assert(preset != RangePreset.custom, 'Use InsightsRange.custom');
    final today = dayOf(now);
    return InsightsRange._(preset, addDays(today, -(preset.days - 1)), today);
  }

  /// The days from [first] to [last], whatever their time of day.
  factory InsightsRange.custom(DateTime first, DateTime last) =>
      InsightsRange._(RangePreset.custom, dayOf(first), dayOf(last));

  final RangePreset preset;

  /// Midnight of the first and last day.
  final DateTime firstDay;
  final DateTime lastDay;

  /// How many calendar days the range covers.
  int get days =>
      DateTime.utc(lastDay.year, lastDay.month, lastDay.day)
          .difference(DateTime.utc(firstDay.year, firstDay.month, firstDay.day))
          .inDays +
      1;

  /// "Last Month", or for a custom range its dates: "Sep 3 – Sep 18".
  String get label => preset == RangePreset.custom ? dates : preset.label;

  /// "Oct 1", "Sep 25 – Oct 1".
  String get dates => days == 1
      ? formatShortDate(firstDay)
      : '${formatShortDate(firstDay)} – ${formatShortDate(lastDay)}';

  @override
  bool operator ==(Object other) =>
      other is InsightsRange &&
      other.preset == preset &&
      other.firstDay == firstDay &&
      other.lastDay == lastDay;

  @override
  int get hashCode => Object.hash(preset, firstDay, lastDay);

  static DateTime dayOf(DateTime time) =>
      DateTime(time.year, time.month, time.day);

  /// Calendar-day arithmetic that keeps the time of day across daylight
  /// saving.
  static DateTime addDays(DateTime date, int days) => DateTime(
    date.year,
    date.month,
    date.day + days,
    date.hour,
    date.minute,
    date.second,
    date.millisecond,
    date.microsecond,
  );
}

/// `Oct 1` — no intl dependency for one format.
String formatShortDate(DateTime date) =>
    '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1]} '
    '${date.day}';

/// One product's sales in a period.
class ProductSales {
  const ProductSales({
    required this.productId,
    required this.name,
    required this.units,
    required this.revenueCentavos,
    this.imageUrl,
  });

  final String productId;
  final String name;
  final int units;
  final int revenueCentavos;
  final String? imageUrl;
}

/// How the Sales Trends chart splits a range into bars.
enum TrendUnit {
  /// One bar per hour: a single day.
  hour,

  /// One bar per day: up to [SalesInsights.maxDailyBars] days.
  day,

  /// One bar per 7 days from the range's first day: longer ranges.
  week,
}

/// One bar of the Sales Trends chart.
class TrendBucket {
  const TrendBucket({
    required this.start,
    required this.end,
    required this.totalCentavos,
    required this.title,
    this.axisLabel,
  });

  final DateTime start;

  /// Exclusive.
  final DateTime end;
  final int totalCentavos;

  /// Under the bar — `MON`, `28`, `Sep 2`, `9a` — or null for an hour that
  /// goes unlabelled so its neighbours have room.
  final String? axisLabel;

  /// What the bar covers, in full: `Tuesday, Sep 29`, `Sep 2 – 8`,
  /// `3 PM – 4 PM`; a short last week says so: `Sep 30 – Oct 1 (2 days)`.
  final String title;

  bool contains(DateTime time) => !time.isBefore(start) && time.isBefore(end);
}

/// What the Analytics tab shows, worked out from the device's sales history
/// and catalog — so it works offline, over the 60 days the device keeps.
///
/// Refunded sales don't count. An edited sale counts as it now stands.
class SalesInsights {
  const SalesInsights({
    required this.range,
    required this.salesCentavos,
    required this.previousSalesCentavos,
    required this.profitCentavos,
    required this.previousProfitCentavos,
    required this.transactions,
    required this.profitIsPartial,
    required this.trendUnit,
    required this.trend,
    required this.bestSellers,
    required this.lowStock,
  });

  /// Works out the insights for [range] as of [now].
  ///
  /// The comparison window is the same number of days immediately before,
  /// cut at the same time of day: "today so far" is compared with yesterday
  /// up to now, not with all of yesterday. When that window reaches back
  /// past the [history] the device keeps, there is no comparison: a partial
  /// earlier total would make any change meaningless.
  factory SalesInsights.compute({
    required List<Sale> sales,
    required List<Product> products,
    required InsightsRange range,
    required int lowStockThreshold,
    required DateTime now,
    Duration history = ProductRepository.salesHistory,
  }) {
    final today = InsightsRange.dayOf(now);
    final start = range.firstDay;
    // A range ending today stops at now; an earlier one at its last moment.
    final end = range.lastDay.isBefore(today)
        ? InsightsRange.addDays(
            range.lastDay,
            1,
          ).subtract(const Duration(microseconds: 1))
        : now;
    final previousStart = InsightsRange.addDays(start, -range.days);
    final previousEnd = InsightsRange.addDays(end, -range.days);
    final comparable = !previousStart.isBefore(now.subtract(history));

    final byId = {for (final p in products) p.id: p};
    final standing = [
      for (final s in sales)
        if (!s.voided) s,
    ];

    bool within(Sale s, DateTime from, DateTime to) =>
        !s.completedAt.isBefore(from) && !s.completedAt.isAfter(to);
    final current = [
      for (final s in standing)
        if (within(s, start, end)) s,
    ];
    final previous = [
      for (final s in standing)
        if (within(s, previousStart, previousEnd)) s,
    ];

    var partial = false;
    int profitOf(List<Sale> sales, {bool track = false}) {
      var profit = 0;
      for (final sale in sales) {
        for (final item in sale.items) {
          final buy = byId[item.productId]?.buyCentavos;
          if (buy == null) {
            // A manual entry, a deleted product, or no buy price: its profit
            // is unknown, so it is left out rather than counted as all profit.
            if (track) partial = true;
            continue;
          }
          profit += (item.unitCentavos - buy) * item.quantity;
        }
      }
      return profit;
    }

    int total(List<Sale> sales) =>
        sales.fold(0, (sum, sale) => sum + sale.totalCentavos);

    // Best sellers: by revenue, then units; manual entries have no product.
    final units = <String, int>{};
    final revenue = <String, int>{};
    final names = <String, String>{};
    for (final sale in current) {
      for (final item in sale.items) {
        final id = item.productId;
        if (id == null) continue;
        units[id] = (units[id] ?? 0) + item.quantity;
        revenue[id] = (revenue[id] ?? 0) + item.totalCentavos;
        names[id] = item.name;
      }
    }
    final bestSellers =
        [
          for (final id in units.keys)
            ProductSales(
              productId: id,
              // The current name if the product still exists, else as sold.
              name: byId[id]?.displayName ?? names[id]!,
              units: units[id]!,
              revenueCentavos: revenue[id]!,
              imageUrl: byId[id]?.imageUrl,
            ),
        ]..sort((a, b) {
          final byRevenue = b.revenueCentavos.compareTo(a.revenueCentavos);
          return byRevenue != 0 ? byRevenue : b.units.compareTo(a.units);
        });

    final unit = range.days == 1
        ? TrendUnit.hour
        : range.days <= maxDailyBars
        ? TrendUnit.day
        : TrendUnit.week;
    final trend = [
      for (final (start, end, title, label) in _buckets(range, unit, current))
        TrendBucket(
          start: start,
          end: end,
          title: title,
          axisLabel: label,
          totalCentavos: total([
            for (final s in current)
              if (!s.completedAt.isBefore(start) && s.completedAt.isBefore(end))
                s,
          ]),
        ),
    ];

    final lowStock =
        [
          for (final p in products)
            if (p.statusFor(lowStockThreshold) != StockStatus.inStock) p,
        ]..sort((a, b) {
          final byStock = a.stock.compareTo(b.stock);
          return byStock != 0
              ? byStock
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

    return SalesInsights(
      range: range,
      salesCentavos: total(current),
      previousSalesCentavos: comparable ? total(previous) : null,
      profitCentavos: profitOf(current, track: true),
      previousProfitCentavos: comparable ? profitOf(previous) : null,
      transactions: current.length,
      profitIsPartial: partial,
      trendUnit: unit,
      trend: trend,
      bestSellers: bestSellers.take(5).toList(),
      lowStock: lowStock,
    );
  }

  final InsightsRange range;
  final int salesCentavos;
  final int profitCentavos;

  /// The same stretch just before [range]; null when it reaches back past
  /// the sales history the device keeps.
  final int? previousSalesCentavos;
  final int? previousProfitCentavos;

  /// Standing sales in the period.
  final int transactions;

  /// Whether some items sold had no known buy price and were left out of
  /// [profitCentavos].
  final bool profitIsPartial;

  /// Ranges longer than this many days are charted by week: more daily bars
  /// would be too thin to read or tap on a phone.
  static const maxDailyBars = 14;

  /// A day's hourly chart always spans at least these hours, widened to
  /// take in any sale outside them.
  static const openingHour = 6;
  static const closingHour = 22;

  final TrendUnit trendUnit;

  /// The Sales Trends bars across [range], oldest first.
  final List<TrendBucket> trend;

  /// Top five by revenue.
  final List<ProductSales> bestSellers;

  /// Low and out-of-stock products, emptiest first.
  final List<Product> lowStock;

  double? get salesChange => _change(salesCentavos, previousSalesCentavos);
  double? get profitChange => _change(profitCentavos, previousProfitCentavos);

  /// Fractional change, e.g. 0.12 for +12%; null when there's nothing to
  /// compare against.
  static double? _change(int current, int? previous) =>
      previous == null || previous <= 0
      ? null
      : (current - previous) / previous;

  /// The bars' spans, titles and axis labels for [range] by [unit].
  static List<(DateTime, DateTime, String, String?)> _buckets(
    InsightsRange range,
    TrendUnit unit,
    List<Sale> sales,
  ) {
    switch (unit) {
      case TrendUnit.hour:
        final day = range.firstDay;
        var first = openingHour;
        var last = closingHour;
        for (final sale in sales) {
          final hour = sale.completedAt.hour;
          if (hour < first) first = hour;
          if (hour + 1 > last) last = hour + 1;
        }
        return [
          for (var h = first; h < last; h++)
            (
              DateTime(day.year, day.month, day.day, h),
              DateTime(day.year, day.month, day.day, h + 1),
              '${_hour(h)} – ${_hour(h + 1)}',
              // Every third hour, so the labels don't run into each other.
              h % 3 == 0 ? _hour(h, short: true) : null,
            ),
        ];

      case TrendUnit.day:
        return [
          for (var i = 0; i < range.days; i++)
            () {
              final day = InsightsRange.addDays(range.firstDay, i);
              return (
                day,
                InsightsRange.addDays(day, 1),
                '${_weekdays[day.weekday - 1]}, ${formatShortDate(day)}',
                range.days <= 7
                    ? _weekdays[day.weekday - 1].substring(0, 3).toUpperCase()
                    : '${day.day}',
              );
            }(),
        ];

      case TrendUnit.week:
        final end = InsightsRange.addDays(range.lastDay, 1);
        return [
          for (
            var start = range.firstDay;
            start.isBefore(end);
            start = InsightsRange.addDays(start, 7)
          )
            () {
              var next = InsightsRange.addDays(start, 7);
              if (next.isAfter(end)) next = end;
              final last = InsightsRange.addDays(next, -1);
              final days = InsightsRange.custom(start, last).days;
              return (
                start,
                next,
                '${_span(start, last)}'
                    '${days < 7 ? ' ($days day${days == 1 ? '' : 's'})' : ''}',
                formatShortDate(start),
              );
            }(),
        ];
    }
  }

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// `3 PM`, or `3p` when [short]; hour 0 and 24 are midnight, `12 AM`.
  static String _hour(int hour, {bool short = false}) {
    final h = hour % 24;
    final twelve = h % 12 == 0 ? 12 : h % 12;
    final am = h < 12;
    return short ? '$twelve${am ? 'a' : 'p'}' : '$twelve ${am ? 'AM' : 'PM'}';
  }

  /// `Sep 2 – 8`, or across months `Sep 30 – Oct 6`; one day is `Sep 2`.
  static String _span(DateTime first, DateTime last) {
    if (first == last) return formatShortDate(first);
    return first.month == last.month
        ? '${formatShortDate(first)} – ${last.day}'
        : '${formatShortDate(first)} – ${formatShortDate(last)}';
  }
}

/// A money axis for a bar chart: gridlines at 0, [step], 2×[step], … up to
/// [max], which is the first gridline at or above [peak]. Steps are round
/// peso amounts — 1, 2 or 5 times a power of ten — so labels read ₱500,
/// ₱1K, ₱1.5K rather than ₱487.
({int max, int step}) chartScale(int peakCentavos, {int lines = 3}) {
  if (peakCentavos <= 0) return (max: 10000, step: 10000 ~/ lines);
  final rough = peakCentavos / lines;
  var magnitude = 1;
  while (magnitude * 10 <= rough) {
    magnitude *= 10;
  }
  final step = [
    1,
    2,
    5,
    10,
  ].map((m) => m * magnitude).firstWhere((s) => s >= rough);
  final max = (peakCentavos / step).ceil() * step;
  return (max: max, step: step);
}

/// `₱950.50`, `₱1.2K`, `₱142.5K`, `₱1.3M` — short enough for a stat tile.
/// Negative amounts (a loss) keep their sign: `-₱1.2K`.
String formatCompactPeso(int centavos) {
  final sign = centavos < 0 ? '-' : '';
  final pesos = centavos.abs() / 100;
  String short(double value, String suffix) {
    final text = value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return '$sign₱$text$suffix';
  }

  // Thresholds sit where one decimal would round up to the next unit, so
  // 999,960 reads ₱1M rather than ₱1000K.
  if (pesos >= 999950) return short(pesos / 1000000, 'M');
  if (pesos >= 1000) return short(pesos / 1000, 'K');
  final whole = centavos.abs() ~/ 100;
  final cents = (centavos.abs() % 100).toString().padLeft(2, '0');
  return '$sign₱$whole.$cents';
}
