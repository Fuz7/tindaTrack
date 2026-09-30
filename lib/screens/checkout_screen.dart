import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/product_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart' show formatPeso;
import 'product_form_screen.dart' show centavosToInput, parseCentavos;

/// How checkout ended, for the cart underneath. Null (a plain back) means
/// "Back to Cart": the cart stays as it was.
enum CheckoutResult { completed, discarded }

/// Checkout — a Flutter build of the Stitch "Checkout" design (project
/// 14772063175572299152): order summary, total, cash as the payment method,
/// amount received with quick-cash keys and change due, and Complete Sale.
///
/// The design's discount / promo code row is left out on purpose. An EXACT
/// key fills in the total, for the common case of paying the exact amount.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.items,
    required this.onComplete,
  });

  final List<SaleItem> items;

  /// Records the sale; the dashboard ends up at [ProductRepository.recordSale].
  /// Completes once it's saved on the device, not on the server.
  final Future<Sale> Function(List<SaleItem> items, int receivedCentavos)
  onComplete;

  static const quickCash = [5000, 10000, 20000, 50000, 100000];

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _received = TextEditingController();
  bool _saving = false;

  late final int _total = widget.items.fold(
    0,
    (total, item) => total + item.totalCentavos,
  );
  late final int _itemCount = widget.items.fold(
    0,
    (count, item) => count + item.quantity,
  );

  int get _receivedCentavos => parseCentavos(_received.text) ?? 0;
  bool get _enough => _receivedCentavos >= _total;

  @override
  void dispose() {
    _received.dispose();
    super.dispose();
  }

  void _setReceived(int? centavos) {
    final text = centavosToInput(centavos ?? 0);
    setState(() {
      _received.value = centavos == null
          ? TextEditingValue.empty
          : TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
            );
    });
  }

  /// Quick-cash keys add up, as when a customer hands over ₱100 and ₱20.
  void _add(int centavos) =>
      _setReceived((_receivedCentavos + centavos).clamp(0, 99999999));

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this sale?'),
        content: const Text('The cart will be cleared.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.actionDestructive,
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context, CheckoutResult.discarded);
    }
  }

  Future<void> _complete() async {
    if (!_enough || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final sale = await widget.onComplete(widget.items, _receivedCentavos);
      if (!mounted) return;
      Navigator.pop(context, CheckoutResult.completed);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              sale.changeCentavos == 0
                  ? 'Sale completed.'
                  : 'Sale completed. Change: ${formatPeso(sale.changeCentavos)}',
            ),
          ),
        );
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not save the sale. Try again.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.stackSm,
                  AppSpacing.gutter,
                  AppSpacing.stackMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopActions(
                      onBack: () => Navigator.maybePop(context),
                      onDiscard: _saving ? null : _discard,
                    ),
                    const SizedBox(height: AppSpacing.stackSm),
                    // Collapsed by default: checkout is about the total and the
                    // cash, so those stay in view; the list is a tap away for
                    // a double-check.
                    _OrderSummary(items: widget.items, itemCount: _itemCount),
                    const SizedBox(height: AppSpacing.stackMd),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'TOTAL',
                          style: AppTypography.headlineMd.copyWith(
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.stackMd),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              formatPeso(_total),
                              style: AppTypography.displayPrice.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    const _SectionLabel('PAYMENT METHOD'),
                    const _CashMethod(),
                    const SizedBox(height: 32),
                    const _SectionLabel('PAYMENT DETAILS'),
                    _PaymentDetails(
                      controller: _received,
                      total: _total,
                      received: _receivedCentavos,
                      onChanged: () => setState(() {}),
                      onAdd: _add,
                      onExact: () => _setReceived(_total),
                      onClear: () => _setReceived(null),
                      onSubmitted: _complete,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.gutter),
              child: SizedBox(
                height: 64,
                child: FilledButton.icon(
                  onPressed: _enough && !_saving ? _complete : null,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : const Icon(Icons.check_circle),
                  label: Text(
                    'COMPLETE SALE',
                    style: AppTypography.headlineMd.copyWith(
                      color: _enough
                          ? AppColors.onPrimary
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    disabledBackgroundColor: AppColors.surfaceContainerHigh,
                    disabledForegroundColor: AppColors.onSurfaceVariant,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
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

class _TopActions extends StatelessWidget {
  const _TopActions({required this.onBack, required this.onDiscard});

  final VoidCallback onBack;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      foregroundColor: AppColors.onSurfaceVariant,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      textStyle: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w500),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Flexible, so large text shortens the labels rather than overflowing.
        Flexible(
          child: TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back to Cart', overflow: TextOverflow.ellipsis),
            style: style,
          ),
        ),
        const SizedBox(width: AppSpacing.stackSm),
        Flexible(
          child: TextButton.icon(
            onPressed: onDiscard,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Discard Sale', overflow: TextOverflow.ellipsis),
            style: style,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.stackMd),
      child: Text(
        text,
        style: AppTypography.labelCaps.copyWith(
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// "ORDER SUMMARY" as a dropdown: a header with the item count and a preview
/// of the names, opening to the full list of lines.
class _OrderSummary extends StatefulWidget {
  const _OrderSummary({required this.items, required this.itemCount});

  final List<SaleItem> items;
  final int itemCount;

  @override
  State<_OrderSummary> createState() => _OrderSummaryState();
}

class _OrderSummaryState extends State<_OrderSummary> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.itemCount;
    final radius = BorderRadius.circular(AppRadius.md);

    return Material(
      color: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ORDER SUMMARY · $count '
                            '${count == 1 ? 'ITEM' : 'ITEMS'}',
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          if (!_open) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.items.map((i) => i.name).join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onSurface,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.expand_more,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Column(
                      children: [
                        for (final item in widget.items)
                          _SummaryLine(item: item),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.item});

  final SaleItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: AppTypography.bodyLg.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  'Qty: ${item.quantity} × ${formatPeso(item.unitCentavos)}',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.stackMd),
          Text(
            formatPeso(item.totalCentavos),
            style: AppTypography.bodyLg.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cash, the only method for now, shown selected as in the design.
class _CashMethod extends StatelessWidget {
  const _CashMethod();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.stackMd),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.payments_outlined,
            size: 30,
            color: AppColors.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CASH',
                  style: AppTypography.labelCaps.copyWith(
                    color: AppColors.onPrimaryContainer,
                  ),
                ),
                Text(
                  'Primary Payment Method',
                  style: AppTypography.bodySm.copyWith(
                    fontSize: 12,
                    color: AppColors.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: AppColors.onPrimaryContainer),
        ],
      ),
    );
  }
}

class _PaymentDetails extends StatelessWidget {
  const _PaymentDetails({
    required this.controller,
    required this.total,
    required this.received,
    required this.onChanged,
    required this.onAdd,
    required this.onExact,
    required this.onClear,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final int total;
  final int received;
  final VoidCallback onChanged;
  final ValueChanged<int> onAdd;
  final VoidCallback onExact;
  final VoidCallback onClear;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final change = received - total;
    final entered = controller.text.isNotEmpty;
    final short = entered && change < 0;

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: BorderSide(color: color, width: width),
        );

    Widget key(String label, VoidCallback onTap, {bool muted = false}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              backgroundColor: muted
                  ? AppColors.surfaceContainer
                  : AppColors.surfaceContainerLowest,
              foregroundColor: muted
                  ? AppColors.onSurfaceVariant
                  : AppColors.onSurface,
              side: const BorderSide(color: AppColors.surfaceBorder),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.base),
              ),
            ),
            child: Text(label, style: AppTypography.labelCaps),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.stackMd),
      decoration: BoxDecoration(
        color: AppColors.surfaceTonal,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'AMOUNT RECEIVED',
            style: AppTypography.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            inputFormatters: [
              // Up to ₱999,999.99, as on the price fields.
              FilteringTextInputFormatter.allow(
                RegExp(r'^\d{0,6}(\.\d{0,2})?'),
              ),
            ],
            onChanged: (_) => onChanged(),
            onSubmitted: (_) => onSubmitted(),
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            style: AppTypography.headlineLg.copyWith(
              color: AppColors.onSurface,
            ),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: AppTypography.headlineLg.copyWith(
                color: AppColors.outline,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Text(
                  '₱',
                  style: AppTypography.headlineLg.copyWith(
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(),
              filled: true,
              fillColor: AppColors.surfaceContainerLowest,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: border(AppColors.surfaceBorder),
              enabledBorder: border(AppColors.surfaceBorder),
              focusedBorder: border(AppColors.primary, 2),
            ),
          ),
          const SizedBox(height: AppSpacing.stackMd),
          Row(
            children: [
              Expanded(
                child: Text(
                  short ? 'SHORT BY' : 'CHANGE DUE',
                  style: AppTypography.labelCaps.copyWith(
                    color: short ? AppColors.error : AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                formatPeso(entered ? change.abs() : 0),
                style: AppTypography.headlineLg.copyWith(
                  color: short
                      ? AppColors.error
                      : change > 0
                      ? AppColors.primary
                      : AppColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.stackSm),
          // EXACT first: paying the exact amount is the most common case.
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: FilledButton.tonal(
                    onPressed: onExact,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryFixed.withValues(
                        alpha: 0.35,
                      ),
                      foregroundColor: AppColors.onPrimaryFixedVariant,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.base),
                      ),
                    ),
                    child: Text(
                      'EXACT ${formatPeso(total)}',
                      style: AppTypography.labelCaps,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              for (final c in CheckoutScreen.quickCash.take(3))
                key(formatPeso(c).replaceAll('.00', ''), () => onAdd(c)),
            ],
          ),
          Row(
            children: [
              for (final c in CheckoutScreen.quickCash.skip(3))
                key(formatPeso(c).replaceAll('.00', ''), () => onAdd(c)),
              key('CLEAR', onClear, muted: true),
            ],
          ),
        ],
      ),
    );
  }
}
