import 'package:flutter/material.dart';

import '../services/product_repository.dart';
import '../services/product_service.dart';
import '../services/sales_insights.dart';
import '../theme/app_theme.dart';
import '../widgets/product_visuals.dart';
import 'home_screen.dart' show formatPeso;

/// The Analytics tab — the Stitch "Analytics Insights" design (project
/// 14772063175572299152): sales and estimated profit for a period, the last
/// seven days as bars, the five best sellers, and what needs restocking.
///
/// Everything is worked out on the device by [SalesInsights] from the same
/// sales history and catalog the other tabs read, so it works offline.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({
    super.key,
    required this.sales,
    required this.products,
    required this.lowStockThreshold,
    required this.onRestock,
    this.clock = DateTime.now,
  });

  final Stream<List<Sale>> sales;
  final Stream<List<Product>> products;
  final Stream<int> lowStockThreshold;

  /// "Restock Now": shows the products that need it.
  final VoidCallback onRestock;

  /// "Now", swappable in tests.
  final DateTime Function() clock;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  /// The picked preset; ignored while [_custom] is set.
  RangePreset _preset = RangePreset.month;

  /// A picked custom range, kept as dates so it doesn't move with the clock.
  InsightsRange? _custom;

  /// Presets are re-worked from the clock each build, so "Today" rolls over
  /// at midnight.
  InsightsRange _range(DateTime now) =>
      _custom ?? InsightsRange.preset(_preset, now);

  Future<void> _pickRange() async {
    final now = widget.clock();
    final current = _range(now);
    final choice = await showModalBottomSheet<RangePreset>(
      context: context,
      showDragHandle: true,
      // Sized to its options rather than capped at half the screen; it
      // scrolls on a short or landscape screen.
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      builder: (context) => _RangeSheet(current: current, now: now),
    );
    if (choice == null || !mounted) return;

    if (choice != RangePreset.custom) {
      setState(() {
        _preset = choice;
        _custom = null;
      });
      return;
    }

    // Only the days the device still holds sales for can be picked.
    final today = InsightsRange.dayOf(now);
    final earliest = InsightsRange.dayOf(
      now.subtract(ProductRepository.salesHistory),
    ).add(const Duration(days: 1));
    final picked = await showDateRangePicker(
      context: context,
      firstDate: earliest,
      lastDate: today,
      currentDate: today,
      initialDateRange: current.firstDay.isBefore(earliest)
          ? null
          : DateTimeRange(start: current.firstDay, end: current.lastDay),
      helpText: 'Select dates',
      // The calendar view's button, and the typed-dates view's.
      saveText: 'Apply',
      confirmText: 'Apply',
    );
    if (picked == null || !mounted) return;
    setState(() => _custom = InsightsRange.custom(picked.start, picked.end));
  }

  // Subscribed once, so rebuilding for a new period doesn't re-listen.
  late final _sales = widget.sales;
  late final _products = widget.products;
  late final _threshold = widget.lowStockThreshold;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Sale>>(
      stream: _sales,
      builder: (context, sales) => StreamBuilder<List<Product>>(
        stream: _products,
        builder: (context, products) => StreamBuilder<int>(
          stream: _threshold,
          builder: (context, threshold) {
            if (!sales.hasData || !products.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final now = widget.clock();
            final insights = SalesInsights.compute(
              sales: sales.data!,
              products: products.data!,
              range: _range(now),
              lowStockThreshold: threshold.data ?? 5,
              now: now,
            );
            return _Insights(
              insights: insights,
              now: now,
              onPickRange: _pickRange,
              onRestock: widget.onRestock,
            );
          },
        ),
      ),
    );
  }
}

class _Insights extends StatelessWidget {
  const _Insights({
    required this.insights,
    required this.now,
    required this.onPickRange,
    required this.onRestock,
  });

  final SalesInsights insights;
  final DateTime now;
  final VoidCallback onPickRange;
  final VoidCallback onRestock;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.gutter,
        AppSpacing.gutter,
        32,
      ),
      children: [
        const _Header(),
        const SizedBox(height: 12),
        _RangeButton(range: insights.range, onTap: onPickRange),
        const SizedBox(height: AppSpacing.stackMd),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.payments_outlined,
                  iconColor: AppColors.primary,
                  label: 'Total Sales',
                  value: formatCompactPeso(insights.salesCentavos),
                  change: insights.salesChange,
                  note:
                      '${insights.transactions} sale'
                      '${insights.transactions == 1 ? '' : 's'}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  icon: Icons.trending_up,
                  iconColor: AppColors.tertiary,
                  label: 'Estimated Profit',
                  value: formatCompactPeso(insights.profitCentavos),
                  change: insights.profitChange,
                  note: insights.profitIsPartial
                      ? 'Items with a buy price'
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.stackMd),
        _TrendCard(
          // A new range starts over on its own default bar.
          key: ValueKey(insights.range),
          trend: insights.trend,
          unit: insights.trendUnit,
          range: insights.range,
          now: now,
        ),
        const SizedBox(height: AppSpacing.stackMd),
        _BestSellers(sellers: insights.bestSellers),
        const SizedBox(height: AppSpacing.stackMd),
        _LowStockCard(products: insights.lowStock, onRestock: onRestock),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DASHBOARD',
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        Text(
          'Business Insights',
          style: AppTypography.headlineMd.copyWith(
            fontWeight: FontWeight.w500,
            color: AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}

/// The period control: a full-width outlined button that reads like a
/// dropdown field — label, the actual dates, and a chevron.
class _RangeButton extends StatelessWidget {
  const _RangeButton({required this.range, required this.onTap});

  final InsightsRange range;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final custom = range.preset == RangePreset.custom;

    return Semantics(
      button: true,
      label: 'Showing ${range.label}, ${range.dates}. Change period',
      excludeSemantics: true,
      child: Material(
        color: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          side: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryFixed.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(AppRadius.base),
                  ),
                  child: Icon(
                    custom ? Icons.date_range : Icons.calendar_today_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        custom ? 'Custom Range' : range.label,
                        style: AppTypography.bodyLg.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        range.dates,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Change',
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const Icon(
                  Icons.expand_more,
                  size: 24,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The period choices, each with the dates it covers. Pops the chosen
/// preset; [RangePreset.custom] means "open the date picker".
class _RangeSheet extends StatelessWidget {
  const _RangeSheet({required this.current, required this.now});

  final InsightsRange current;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    Widget option({
      required RangePreset preset,
      required String subtitle,
      required IconData icon,
    }) {
      final selected = current.preset == preset;
      return ListTile(
        selected: selected,
        selectedTileColor: AppColors.primaryFixed.withValues(alpha: 0.2),
        selectedColor: AppColors.primary,
        leading: Icon(icon),
        title: Text(
          preset.label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: preset == RangePreset.custom
            ? const Icon(Icons.chevron_right)
            : selected
            ? const Icon(Icons.check)
            : null,
        onTap: () => Navigator.of(context).pop(preset),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                0,
                AppSpacing.gutter,
                8,
              ),
              child: Text(
                'Show sales for',
                style: AppTypography.headlineMd.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
            ),
            for (final preset in [
              RangePreset.today,
              RangePreset.week,
              RangePreset.month,
            ])
              option(
                preset: preset,
                subtitle: InsightsRange.preset(preset, now).dates,
                icon: Icons.calendar_today_outlined,
              ),
            const Divider(height: 1),
            option(
              preset: RangePreset.custom,
              subtitle: current.preset == RangePreset.custom
                  ? current.dates
                  : 'Pick start and end dates',
              icon: Icons.date_range,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                8,
                AppSpacing.gutter,
                16,
              ),
              child: Text(
                'This phone keeps the last 60 days of sales.',
                style: AppTypography.bodySm.copyWith(
                  fontSize: 12,
                  color: AppColors.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A KPI tile: icon, change against the previous period, label, value.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.change,
    this.note,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  /// Null when there is no earlier period to compare with.
  final double? change;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final change = this.change;

    return _Card(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const Spacer(),
              if (change != null) _ChangeBadge(change: change),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: AppTypography.bodySm.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTypography.headlineMd.copyWith(
                fontWeight: FontWeight.w500,
                color: AppColors.onSurface,
              ),
            ),
          ),
          if (note != null)
            Text(
              note!,
              style: AppTypography.bodySm.copyWith(
                fontSize: 12,
                color: AppColors.outline,
              ),
            ),
        ],
      ),
    );
  }
}

/// `+12%` in green or `-8%` in red; the arrow carries the direction too, so
/// it isn't color alone.
class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({required this.change});

  final double change;

  @override
  Widget build(BuildContext context) {
    final percent = (change * 100).abs();
    final text = percent >= 10
        ? percent.round().toString()
        : percent.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    final up = change >= 0;
    final color = up ? AppColors.primaryContainer : AppColors.error;

    return Semantics(
      label: '${up ? 'Up' : 'Down'} $text percent from the previous period',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.arrow_upward : Icons.arrow_downward,
            size: 12,
            color: color,
          ),
          Text(
            '${up ? '+' : '-'}$text%',
            style: AppTypography.bodySm.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sales across the picked range — by hour for one day, by day up to two
/// weeks, by week beyond — on a ₱ scale. Tapping a bar shows its exact total
/// in the card's header.
class _TrendCard extends StatefulWidget {
  const _TrendCard({
    super.key,
    required this.trend,
    required this.unit,
    required this.range,
    required this.now,
  });

  final List<TrendBucket> trend;
  final TrendUnit unit;
  final InsightsRange range;
  final DateTime now;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  /// The bars' area; the axis labels sit beside it and below it.
  static const _plotHeight = 140.0;

  /// Room above the plot for a full-height bar's amount.
  static const _headroom = 16.0;
  static const _axisWidth = 40.0;

  /// Amounts go on the bars themselves only while they fit side by side.
  static const _maxLabelledBars = 9;

  /// Index into the bars; until one is tapped, the one holding "now", or
  /// else the last.
  int? _selected;

  int get _defaultSelected {
    final now = widget.trend.indexWhere((b) => b.contains(widget.now));
    return now >= 0 ? now : widget.trend.length - 1;
  }

  String get _byWhat => switch (widget.unit) {
    TrendUnit.hour => 'by hour',
    TrendUnit.day => 'by day',
    TrendUnit.week => 'by week',
  };

  @override
  Widget build(BuildContext context) {
    final trend = widget.trend;
    final selected = _selected ?? _defaultSelected;
    final bucket = trend[selected];
    final peak = trend.fold(
      0,
      (m, b) => b.totalCentavos > m ? b.totalCentavos : m,
    );
    final scale = chartScale(peak);
    final labelBars = trend.length <= _maxLabelledBars;
    final isToday =
        widget.unit == TrendUnit.day &&
        bucket.start == InsightsRange.dayOf(widget.now);

    return _Card(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sales Trends',
                      style: AppTypography.bodyLg.copyWith(
                        fontSize: 17,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      '${widget.range.dates} · $_byWhat',
                      style: AppTypography.bodySm.copyWith(
                        fontSize: 12,
                        color: AppColors.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Sized to its text and pinned to the right edge; capped so a
              // long week title wraps rather than squeezing the heading.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatPeso(bucket.totalCentavos),
                      textAlign: TextAlign.end,
                      style: AppTypography.bodyLg.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      isToday ? 'Today' : bucket.title,
                      textAlign: TextAlign.end,
                      style: AppTypography.bodySm.copyWith(
                        fontSize: 12,
                        color: AppColors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.stackMd),
          SizedBox(
            height: _headroom + _plotHeight + 24,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MoneyAxis(
                  scale: scale,
                  width: _axisWidth,
                  top: _headroom,
                  height: _plotHeight,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      _Gridlines(
                        scale: scale,
                        top: _headroom,
                        height: _plotHeight,
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, b) in trend.indexed)
                            Expanded(
                              child: _Bar(
                                label: b.axisLabel,
                                amount: labelBars && b.totalCentavos > 0
                                    ? formatCompactPeso(b.totalCentavos)
                                    : null,
                                fraction: b.totalCentavos / scale.max,
                                selected: i == selected,
                                plotHeight: _plotHeight,
                                headroom: _headroom,
                                semanticLabel:
                                    '${b.title}: ${formatPeso(b.totalCentavos)}',
                                onTap: () => setState(() => _selected = i),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The ₱ labels down the chart's left edge, one per gridline.
class _MoneyAxis extends StatelessWidget {
  const _MoneyAxis({
    required this.scale,
    required this.width,
    required this.top,
    required this.height,
  });

  final ({int max, int step}) scale;
  final double width;
  final double top;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: top + height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var v = 0; v <= scale.max; v += scale.step)
              Positioned(
                left: 0,
                right: 6,
                top: top + height * (1 - v / scale.max) - 7,
                child: Text(
                  v == 0 ? '₱0' : formatCompactPeso(v).replaceAll('.00', ''),
                  textAlign: TextAlign.end,
                  style: AppTypography.bodySm.copyWith(
                    fontSize: 10,
                    height: 1.4,
                    color: AppColors.outline,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Faint horizontal lines at each step; the zero line is the solid baseline.
class _Gridlines extends StatelessWidget {
  const _Gridlines({
    required this.scale,
    required this.top,
    required this.height,
  });

  final ({int max, int step}) scale;
  final double top;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          for (var v = 0; v <= scale.max; v += scale.step)
            Positioned(
              left: 0,
              right: 0,
              top: top + height * (1 - v / scale.max) - (v == 0 ? 1 : 0.5),
              child: Container(
                height: v == 0 ? 1 : 0.5,
                color: v == 0
                    ? AppColors.outlineVariant
                    : AppColors.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.amount,
    required this.fraction,
    required this.selected,
    required this.plotHeight,
    required this.headroom,
    required this.semanticLabel,
    required this.onTap,
  });

  /// Under the bar; null leaves the slot blank.
  final String? label;

  /// Over the bar; null when bars are too many or the total is zero.
  final String? amount;

  /// Of the axis' top, 0–1.
  final double fraction;
  final bool selected;
  final double plotHeight;
  final double headroom;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A bar with no sales keeps a stub, so the baseline reads as zero, not
    // as a gap.
    final height = fraction <= 0
        ? 2.0
        : (plotHeight * fraction).clamp(4.0, plotHeight);
    final ink = selected ? AppColors.primary : AppColors.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.base),
        child: Column(
          children: [
            SizedBox(
              height: headroom + plotHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (amount != null)
                    SizedBox(
                      height: headroom,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          amount!,
                          style: AppTypography.bodySm.copyWith(
                            fontSize: 10,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: ink,
                          ),
                        ),
                      ),
                    ),
                  // Thin bars with a little air between them, never wider
                  // than the design's 24px.
                  FractionallySizedBox(
                    widthFactor: 0.62,
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 24),
                        height: height,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary
                              : AppColors.primary.withValues(alpha: 0.35),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 16,
              child: label == null
                  ? null
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label!,
                        maxLines: 1,
                        style: AppTypography.bodySm.copyWith(
                          fontSize: 11,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: ink,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BestSellers extends StatelessWidget {
  const _BestSellers({required this.sellers});

  final List<ProductSales> sellers;

  @override
  Widget build(BuildContext context) {
    final top = sellers.isEmpty ? 0 : sellers.first.revenueCentavos;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(color: AppColors.outlineVariant),
              ),
            ),
            child: Text(
              'Best Sellers (Top 5)',
              style: AppTypography.bodyLg.copyWith(
                fontSize: 17,
                color: AppColors.onSurface,
              ),
            ),
          ),
          if (sellers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No products sold in this period yet.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          for (final (i, seller) in sellers.indexed) ...[
            if (i > 0)
              const Divider(height: 1, color: AppColors.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.gutter),
              child: Row(
                children: [
                  ProductImage(
                    url: seller.imageUrl,
                    bytes: seller.imageBytes,
                    size: 48,
                    radius: 8,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          seller.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyLg.copyWith(
                            fontWeight: FontWeight.w400,
                            color: AppColors.onSurface,
                          ),
                        ),
                        Text(
                          '${seller.units} Unit${seller.units == 1 ? '' : 's'} '
                          'Sold',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 96,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            formatPeso(seller.revenueCentavos),
                            style: AppTypography.bodyLg.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          child: LinearProgressIndicator(
                            value: top == 0 ? 0 : seller.revenueCentavos / top,
                            minHeight: 4,
                            color: AppColors.primary,
                            backgroundColor: AppColors.surfaceContainerHigh,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LowStockCard extends StatelessWidget {
  const _LowStockCard({required this.products, required this.onRestock});

  final List<Product> products;
  final VoidCallback onRestock;

  static const _shown = 5;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return _Card(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Everything is well stocked.',
                style: AppTypography.bodyLg.copyWith(
                  fontWeight: FontWeight.w400,
                  color: AppColors.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final more = products.length - _shown;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_rounded, color: AppColors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Low Stock Alert (${products.length} '
                  'item${products.length == 1 ? '' : 's'})',
                  style: AppTypography.bodyLg.copyWith(
                    fontWeight: FontWeight.w400,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final product in products.take(_shown)) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(AppRadius.base),
                border: Border.all(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      product.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyLg.copyWith(
                        fontWeight: FontWeight.w400,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${product.stock < 0 ? 0 : product.stock} Left',
                    style: AppTypography.bodyLg.copyWith(
                      fontWeight: FontWeight.w600,
                      color: product.stock <= 0
                          ? AppColors.statusOutOfStock
                          : AppColors.statusLowStock,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'and $more more',
                textAlign: TextAlign.center,
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: AppSpacing.touchTarget + 4,
            child: FilledButton(
              onPressed: onRestock,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.actionDestructive,
                foregroundColor: AppColors.onError,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.base),
                ),
              ),
              child: const Text(
                'RESTOCK NOW',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// White, bordered, rounded — the design's card.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: child,
    );
  }
}
