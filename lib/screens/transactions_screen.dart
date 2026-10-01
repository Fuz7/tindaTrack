import 'dart:async';

import 'package:flutter/material.dart';

import '../services/product_service.dart';
import '../theme/app_theme.dart';
import 'edit_transaction_screen.dart';
import 'home_screen.dart' show formatPeso;

/// The Transactions tab — a Flutter build of the Stitch "Transactions
/// (Refined Hierarchy)" design (project 14772063175572299152): one day's
/// sales at a time, with search, the day's total and order count, and a card
/// per sale that opens to its lines and a Refund.
///
/// Sales come live from Firestore, which serves them from its on-phone cache
/// when offline. The
/// design's Receipt button is left out: there is no printer support. Cards
/// show the customer ("Walk-in Customer" until an edit names one) and the
/// cashier who rang the sale up.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    super.key,
    required this.sales,
    required this.onRefund,
    required this.products,
    required this.onEdit,
    this.now = DateTime.now,
  });

  /// The history, newest first; the dashboard passes
  /// [ProductRepository.watchSales].
  final Stream<List<Sale>> sales;

  /// Voids a sale and returns its items to stock; the dashboard passes
  /// [ProductRepository.voidSale].
  final Future<void> Function(Sale sale) onRefund;

  /// The catalog, for how much stock an edit may take; the dashboard
  /// passes [ProductRepository.watch].
  final Stream<List<Product>> products;

  /// Saves an edited sale.
  final SaleEditor onEdit;

  /// The clock, for "Today"; tests fix it.
  final DateTime Function() now;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _search = TextEditingController();

  /// The day shown, at midnight. Starts on today.
  late DateTime _day = _dateOnly(widget.now());

  /// The one card opened to its lines, if any.
  String? _openId;

  /// The latest catalog, from [TransactionsScreen.products].
  List<Product> _products = const [];
  late final StreamSubscription<List<Product>> _productsSub;

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  bool get _isToday => _day == _dateOnly(widget.now());

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _productsSub = widget.products.listen(
      (products) => _products = products,
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _productsSub.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final today = _dateOnly(widget.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today,
      helpText: 'Show sales from',
    );
    if (picked != null) setState(() => _day = _dateOnly(picked));
  }

  void _edit(Sale sale) {
    Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => EditTransactionScreen(
          sale: sale,
          products: _products,
          onSave: widget.onEdit,
        ),
      ),
    );
  }

  Future<void> _refund(Sale sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Refund ${sale.code}?'),
        content: Text(
          '${formatPeso(sale.totalCentavos)} goes back to the customer and '
          'the items return to stock. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.actionDestructive,
            ),
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onRefund(sale);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${sale.code} refunded.')));
    } on Object {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not refund ${sale.code}. Try again.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Sale>>(
      stream: widget.sales,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Sale>[];
        final onDay = [
          for (final s in all)
            if (_dateOnly(s.completedAt) == _day) s,
        ];
        final query = _search.text.trim().toLowerCase();
        final shown = query.isEmpty
            ? onDay
            : [
                for (final s in onDay)
                  if (s.code.toLowerCase().contains(query) ||
                      (s.customerName?.toLowerCase().contains(query) ??
                          false) ||
                      s.items.any((i) => i.name.toLowerCase().contains(query)))
                    s,
              ];
        // The day's figures leave refunds out, and ignore the search box:
        // they describe the day, not the filtered list.
        final standing = [
          for (final s in onDay)
            if (!s.voided) s,
        ];
        final total = standing.fold(0, (t, s) => t + s.totalCentavos);

        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.stackMd,
            AppSpacing.gutter,
            24,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Transactions',
                    style: AppTypography.headlineLg.copyWith(
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                _DayChip(
                  label: _dayLabel(_day, widget.now()),
                  // Tapping a past day's chip goes back to today.
                  onClear: _isToday
                      ? null
                      : () => setState(() => _day = _dateOnly(widget.now())),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.stackSm),
            Row(
              children: [
                Expanded(child: _SearchField(controller: _search)),
                const SizedBox(width: AppSpacing.stackSm),
                SizedBox.square(
                  dimension: 44,
                  child: IconButton(
                    tooltip: 'Pick a day',
                    onPressed: _pickDay,
                    icon: const Icon(Icons.calendar_today_outlined),
                    color: AppColors.onSurfaceVariant,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.surfaceContainerLowest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.base),
                        side: const BorderSide(color: AppColors.outlineVariant),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.stackMd),
            Row(
              children: [
                Expanded(
                  child: _SummaryTile(
                    label: 'TOTAL SALES',
                    value: formatPeso(total),
                    background: AppColors.primaryContainer,
                    foreground: AppColors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AppSpacing.stackSm),
                Expanded(
                  child: _SummaryTile(
                    label: 'ORDERS',
                    value: '${standing.length}',
                    background: AppColors.surfaceContainerHigh,
                    foreground: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.stackMd),
            if (!snapshot.hasData)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (shown.isEmpty)
              _Empty(
                title: onDay.isEmpty
                    ? (_isToday ? 'No sales yet today' : 'No sales on this day')
                    : 'No matching sales',
                body: onDay.isEmpty
                    ? 'Completed sales show up here.'
                    : 'Try another item name or TX code.',
              )
            else
              for (final sale in shown) ...[
                _SaleCard(
                  sale: sale,
                  open: sale.id == _openId,
                  onTap: () => setState(
                    () => _openId = sale.id == _openId ? null : sale.id,
                  ),
                  onRefund: () => _refund(sale),
                  onEdit: () => _edit(sale),
                ),
                const SizedBox(height: AppSpacing.stackSm),
              ],
          ],
        );
      },
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Today", "Yesterday", or e.g. "Sep 28" ("Sep 28, 2025" in another year).
String _dayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  final label = '${_months[day.month - 1]} ${day.day}';
  return day.year == now.year ? label : '$label, ${day.year}';
}

String _time(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label, required this.onClear});

  final String label;

  /// Set when a past day is shown: the chip then clears back to today.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final chip = Material(
      color: onClear == null
          ? AppColors.surfaceContainer
          : AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onClear,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.labelCaps.copyWith(
                  color: onClear == null
                      ? AppColors.outline
                      : AppColors.onPrimaryContainer,
                ),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.close,
                  size: 14,
                  color: AppColors.onPrimaryContainer,
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return onClear == null
        ? chip
        : Tooltip(message: 'Back to today', child: chip);
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.base),
      borderSide: BorderSide(color: color),
    );
    return TextField(
      controller: controller,
      style: AppTypography.bodySm.copyWith(color: AppColors.onSurface),
      decoration: InputDecoration(
        hintText: 'Search item or TX code...',
        hintStyle: AppTypography.bodySm.copyWith(
          color: AppColors.onSurfaceVariant,
        ),
        prefixIcon: const Icon(
          Icons.search,
          size: 20,
          color: AppColors.outline,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, size: 18),
                onPressed: controller.clear,
              ),
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: border(AppColors.outlineVariant),
        enabledBorder: border(AppColors.outlineVariant),
        focusedBorder: border(AppColors.primary),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.background,
    required this.foreground,
  });

  final String label;
  final String value;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.labelCaps.copyWith(
              color: foreground.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTypography.headlineMd.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({
    required this.sale,
    required this.open,
    required this.onTap,
    required this.onRefund,
    required this.onEdit,
  });

  final Sale sale;
  final bool open;
  final VoidCallback onTap;
  final VoidCallback onRefund;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final voided = sale.voided;
    final radius = BorderRadius.circular(AppRadius.md);
    final count = sale.itemCount;
    final cashier = sale.cashierName;
    final countText =
        '$count ${count == 1 ? 'Item' : 'Items'} Purchased'
        '${cashier == null ? '' : ' · by $cashier'}';
    final strike = voided ? TextDecoration.lineThrough : null;

    final card = Material(
      color: voided
          ? AppColors.surfaceContainerLow
          : AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: open && !voided ? AppColors.primary : AppColors.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
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
                          _time(sale.completedAt),
                          style: AppTypography.labelCaps.copyWith(
                            color: AppColors.outline,
                          ),
                        ),
                        Text(
                          sale.customerName ?? 'Walk-in Customer',
                          style: AppTypography.bodyLg.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            sale.code,
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.outline,
                            ),
                          ),
                          if (voided) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                              child: Text(
                                'VOIDED',
                                style: AppTypography.labelCaps.copyWith(
                                  fontSize: 10,
                                  color: AppColors.onError,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        formatPeso(sale.totalCentavos),
                        style: AppTypography.headlineMd.copyWith(
                          color: voided ? AppColors.outline : AppColors.primary,
                          decoration: strike,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.stackSm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      countText,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                        decoration: strike,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more,
                      size: 20,
                      color: AppColors.outline,
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: open
                    ? _SaleDetails(
                        sale: sale,
                        onRefund: onRefund,
                        onEdit: onEdit,
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      expanded: open,
      label: voided ? '${sale.code}, voided' : null,
      child: Opacity(opacity: voided ? 0.7 : 1, child: card),
    );
  }
}

class _SaleDetails extends StatelessWidget {
  const _SaleDetails({
    required this.sale,
    required this.onRefund,
    required this.onEdit,
  });

  final Sale sale;
  final VoidCallback onRefund;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final line = AppTypography.bodySm.copyWith(color: AppColors.onSurface);
    final muted = AppTypography.bodySm.copyWith(
      color: AppColors.onSurfaceVariant,
    );

    Widget row(String left, String right, TextStyle style) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(left, style: style)),
          const SizedBox(width: AppSpacing.stackSm),
          Text(right, style: style.copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, color: AppColors.outlineVariant),
          const SizedBox(height: AppSpacing.stackSm),
          for (final item in sale.items)
            row(
              '${item.quantity}x ${item.name}',
              formatPeso(item.totalCentavos),
              line,
            ),
          const SizedBox(height: 4),
          row('Cash received', formatPeso(sale.receivedCentavos), muted),
          row('Change', formatPeso(sale.changeCentavos), muted),
          const SizedBox(height: AppSpacing.stackSm),
          if (sale.voided)
            Text(
              'Refunded ${_whenAfter(sale.voidedAt!, sale.completedAt)} — items went back to stock.',
              style: muted.copyWith(fontStyle: FontStyle.italic),
            )
          else ...[
            if (sale.editedAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.stackSm),
                child: Text(
                  'Edited ${_whenAfter(sale.editedAt!, sale.completedAt)}'
                  '${sale.editedBy == null ? '' : ' by ${sale.editedBy}'}.',
                  style: muted.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text('EDIT', style: AppTypography.labelCaps),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.surfaceContainerHighest,
                      foregroundColor: AppColors.onSurfaceVariant,
                      minimumSize: const Size.fromHeight(40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.base),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.stackSm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onRefund,
                    icon: const Icon(Icons.undo, size: 18),
                    label: Text('REFUND', style: AppTypography.labelCaps),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.errorContainer,
                      foregroundColor: AppColors.onErrorContainer,
                      minimumSize: const Size.fromHeight(40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.base),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// When something happened to a sale (a refund, an edit): "14:02" on the
/// day of the sale, else "Sep 29, 14:02".
String _whenAfter(DateTime at, DateTime sold) {
  final sameDay =
      at.year == sold.year && at.month == sold.month && at.day == sold.day;
  return sameDay
      ? _time(at)
      : '${_months[at.month - 1]} ${at.day}, ${_time(at)}';
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 40,
            color: AppColors.outline,
          ),
          const SizedBox(height: AppSpacing.stackMd),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.bodyLg.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: AppSpacing.stackSm),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
