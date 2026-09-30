import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/product_search.dart';
import '../services/product_service.dart';
import '../theme/app_theme.dart';
import '../widgets/product_visuals.dart';
import 'home_screen.dart' show formatPeso;
import 'product_form_screen.dart' show centavosToInput, parseCentavos;

/// Saves an edited sale; the dashboard ends up at
/// [ProductRepository.editSale].
typedef SaleEditor =
    Future<Sale> Function(
      Sale sale, {
      required List<SaleItem> items,
      required int receivedCentavos,
      required String? customerName,
    });

/// "Edit Transaction" — a Flutter build of the Stitch design of that name
/// (project 14772063175572299152): the sale's code, time and cashier, an
/// optional customer name, its lines with quantity steppers, and the cash
/// received. Pops `true` once saved.
///
/// A manual entry rung up in a rush can be linked to the inventory product
/// it really was: the line takes that product's price, and saving takes its
/// stock, since an edit moves stock by the difference per product.
///
/// Left out of the design on purpose: the discount row (there are no
/// discounts), GCash (cash only), and adding products to a past sale.
/// The time and cashier are shown but not editable, so the record of when
/// and by whom a sale was made stays trustworthy; the edit itself is stamped
/// with its own time and editor.
class EditTransactionScreen extends StatefulWidget {
  const EditTransactionScreen({
    super.key,
    required this.sale,
    required this.products,
    required this.onSave,
  });

  final Sale sale;

  /// The current catalog: stock caps how far a quantity can go up, and a
  /// manual entry can be linked to one of these products.
  final List<Product> products;
  final SaleEditor onSave;

  /// A manual entry has no stock to run out of; this keeps it on one line.
  static const maxManualQuantity = 999;

  @override
  State<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  late final List<SaleItem> _items = List.of(widget.sale.items);

  /// Per line, the manual entry it was linked from in this edit, so the
  /// link can be undone and the row can say what it replaced.
  late final List<SaleItem?> _linkedFrom = List.filled(
    _items.length,
    null,
    growable: true,
  );

  late final Map<String, int> _stockOf = {
    for (final p in widget.products) p.id: p.stock,
  };
  late final _customer = TextEditingController(
    text: widget.sale.customerName ?? '',
  );
  late final _received = TextEditingController(
    text: centavosToInput(widget.sale.receivedCentavos),
  );
  bool _saving = false;

  int get _total => _items.fold(0, (t, i) => t + i.totalCentavos);
  int get _receivedCentavos => parseCentavos(_received.text) ?? 0;

  bool get _changed =>
      _receivedCentavos != widget.sale.receivedCentavos ||
      _customer.text.trim() != (widget.sale.customerName ?? '') ||
      _items.length != widget.sale.items.length ||
      [
        for (var i = 0; i < _items.length; i++)
          _items[i].quantity != widget.sale.items[i].quantity ||
              _items[i].name != widget.sale.items[i].name ||
              _items[i].productId != widget.sale.items[i].productId,
      ].any((d) => d);

  bool get _canSave => _changed && _receivedCentavos >= _total && !_saving;

  @override
  void initState() {
    super.initState();
    _customer.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _customer.dispose();
    _received.dispose();
    super.dispose();
  }

  void _setQuantity(int index, int quantity) {
    final item = _items[index];
    setState(() {
      _items[index] = SaleItem(
        productId: item.productId,
        name: item.name,
        unitCentavos: item.unitCentavos,
        quantity: quantity,
      );
    });
  }

  /// Turns the manual entry at [index] into an inventory product picked from
  /// the catalog, so the sale takes that product's stock.
  ///
  /// The line takes the product's sell price, and a quantity guessed from
  /// what was typed: a ₱40 entry linked to a ₱20 Coke becomes 2 — then
  /// capped by what's on the shelf. The stepper fixes any wrong guess.
  Future<void> _link(int index) async {
    final manual = _items[index];
    final product = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _ProductPicker(
        products: widget.products,
        available: (p) => _availableFor(p.id, excludingIndex: index),
      ),
    );
    if (product == null || !mounted) return;

    final available = _availableFor(product.id, excludingIndex: index);
    final guess = product.sellCentavos <= 0
        ? manual.quantity
        : (manual.totalCentavos / product.sellCentavos).round();
    setState(() {
      _linkedFrom[index] ??= manual;
      _items[index] = SaleItem(
        productId: product.id,
        name: product.displayName,
        unitCentavos: product.sellCentavos,
        quantity: guess.clamp(1, math.max(1, available)),
      );
    });
  }

  /// Units of product [id] a line may hold: what the original sale took of
  /// it plus what's on the shelf, less what other lines hold now.
  int _availableFor(String id, {required int excludingIndex}) {
    final original = widget.sale.items
        .where((i) => i.productId == id)
        .fold(0, (n, i) => n + i.quantity);
    var others = 0;
    for (final (i, item) in _items.indexed) {
      if (i != excludingIndex && item.productId == id) others += item.quantity;
    }
    return math.max(0, original + (_stockOf[id] ?? 0) - others);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await widget.onSave(
        widget.sale,
        items: List.of(_items),
        receivedCentavos: _receivedCentavos,
        customerName: _customer.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${saved.code} updated.')));
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'transactions',
          context: ErrorDescription('while saving a sale edit'),
        ),
      );
      if (!mounted) return;
      setState(() => _saving = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not update ${widget.sale.code}.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    final change = _receivedCentavos - _total;
    final count = _items.fold(0, (n, i) => n + i.quantity);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Go back',
                    icon: const Icon(Icons.arrow_back),
                    color: AppColors.primary,
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Edit Transaction',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.headlineMd.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                    _Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _ReadOnly(
                                  label: 'TRANSACTION ID',
                                  value: sale.code,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _ReadOnly(
                                  label: 'DATE & TIME',
                                  value: _dateTime(sale.completedAt),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _ReadOnly(
                            label: 'CASHIER',
                            value: sale.cashierName ?? '—',
                          ),
                          const SizedBox(height: 12),
                          _Label('CUSTOMER NAME'),
                          TextField(
                            controller: _customer,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 40,
                            style: AppTypography.bodyLg.copyWith(
                              color: AppColors.onSurface,
                            ),
                            decoration: _inputDecoration(
                              hint: 'Optional — e.g. Aling Nena',
                            ).copyWith(counterText: ''),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(child: _Label('PURCHASED ITEMS')),
                        Text(
                          '$count ${count == 1 ? 'ITEM' : 'ITEMS'}',
                          style: AppTypography.labelCaps.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.stackSm),
                    for (final (index, item) in _items.indexed) ...[
                      _ItemRow(
                        item: item,
                        max: item.productId == null
                            ? EditTransactionScreen.maxManualQuantity
                            : _availableFor(
                                item.productId!,
                                excludingIndex: index,
                              ),
                        // The last line can't go: an empty sale is a refund.
                        canRemove: _items.length > 1,
                        onQuantity: (q) => _setQuantity(index, q),
                        onRemove: () => setState(() {
                          _items.removeAt(index);
                          _linkedFrom.removeAt(index);
                        }),
                        linkedFrom: _linkedFrom[index],
                        onLink: item.productId == null
                            ? () => _link(index)
                            : null,
                        onUnlink: _linkedFrom[index] == null
                            ? null
                            : () => setState(() {
                                _items[index] = _linkedFrom[index]!;
                                _linkedFrom[index] = null;
                              }),
                      ),
                      const SizedBox(height: AppSpacing.stackSm),
                    ],
                    if (_items.length == 1)
                      Text(
                        'To undo the whole sale, use Refund instead.',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 24),
                    _Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Label('PAYMENT INFORMATION'),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.payments_outlined,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Cash',
                                style: AppTypography.bodyLg.copyWith(
                                  color: AppColors.onSurface,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Amount Received',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _received,
                            textAlign: TextAlign.end,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d{0,6}(\.\d{0,2})?'),
                              ),
                            ],
                            onChanged: (_) => setState(() {}),
                            style: AppTypography.bodyLg.copyWith(
                              color: AppColors.onSurface,
                            ),
                            decoration: _inputDecoration(
                              hint: '0.00',
                            ).copyWith(prefixText: '₱  '),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.stackMd),
                    const Divider(color: AppColors.outlineVariant),
                    _TotalRow(label: 'Total', value: formatPeso(_total)),
                    _TotalRow(
                      label: change < 0 ? 'Short by' : 'Change',
                      value: formatPeso(change.abs()),
                      color: change < 0 ? AppColors.error : null,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.stackSm,
                AppSpacing.gutter,
                AppSpacing.stackSm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: _canSave ? _save : null,
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
                      child: Text(
                        'Update Transaction',
                        style: AppTypography.headlineMd,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.maybePop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.onSurfaceVariant,
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: Text('Cancel Changes', style: AppTypography.bodyLg),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _dateTime(DateTime t) =>
    '${_months[t.month - 1]} ${t.day}, ${t.year} · '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

InputDecoration _inputDecoration({required String hint}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.base),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: AppTypography.bodySm.copyWith(color: AppColors.outline),
    isDense: true,
    filled: true,
    fillColor: AppColors.surfaceContainerLowest,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    border: border(AppColors.outline),
    enabledBorder: border(AppColors.outline),
    focusedBorder: border(AppColors.primary, 2),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.stackMd + 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: child,
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: AppTypography.labelCaps.copyWith(
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ReadOnly extends StatelessWidget {
  const _ReadOnly({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(label),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.base),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.max,
    required this.canRemove,
    required this.onQuantity,
    required this.onRemove,
    this.linkedFrom,
    this.onLink,
    this.onUnlink,
  });

  final SaleItem item;
  final int max;
  final bool canRemove;
  final ValueChanged<int> onQuantity;
  final VoidCallback onRemove;

  /// The manual entry this line was linked from, during this edit.
  final SaleItem? linkedFrom;

  /// Set on a manual entry: picks the inventory product it really was.
  final VoidCallback? onLink;

  /// Set on a line linked during this edit: puts the manual entry back.
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, String tooltip, VoidCallback? onPressed) =>
        SizedBox.square(
          dimension: 36,
          child: IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            iconSize: 18,
            icon: Icon(icon),
            color: AppColors.onSurface,
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlineVariant),
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
                  formatPeso(item.unitCentavos),
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                if (linkedFrom != null)
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Was ${linkedFrom!.name} · '
                          '${formatPeso(linkedFrom!.totalCentavos)}',
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySm.copyWith(
                            fontSize: 12,
                            color: AppColors.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      _SmallLink(label: 'Undo', onTap: onUnlink),
                    ],
                  )
                else if (onLink != null)
                  _SmallLink(
                    label: 'Link to product',
                    icon: Icons.link,
                    onTap: onLink,
                  ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.base),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                step(
                  Icons.remove,
                  'Remove one ${item.name}',
                  item.quantity > 1
                      ? () => onQuantity(item.quantity - 1)
                      : null,
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${item.quantity}',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyLg.copyWith(
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                step(
                  Icons.add,
                  'Add one ${item.name}',
                  item.quantity < max
                      ? () => onQuantity(item.quantity + 1)
                      : null,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: canRemove ? 'Remove ${item.name}' : 'Refund to remove all',
            onPressed: canRemove ? onRemove : null,
            icon: const Icon(Icons.close),
            color: AppColors.error,
          ),
        ],
      ),
    );
  }
}

/// A compact text button for the item rows: "Link to product", "Undo".
class _SmallLink extends StatelessWidget {
  const _SmallLink({required this.label, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Picks the inventory product a manual entry really was, with the same
/// forgiving search as the Home tab. Pops the product; products with none
/// to spare can't be picked.
class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.products, required this.available});

  final List<Product> products;

  /// Units of a product the line could take.
  final int Function(Product product) available;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final shown = query.isEmpty
        ? widget.products
        : [for (final m in searchProducts(widget.products, query)) m.product];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.stackMd,
              AppSpacing.gutter,
              AppSpacing.stackSm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Link to product',
                        style: AppTypography.headlineMd.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Text(
                  'The line takes the product\'s price, and its stock goes '
                  'down when you save.',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search products...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.base),
                      borderSide: const BorderSide(
                        color: AppColors.outlineVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.stackSm),
                Flexible(
                  child: shown.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(AppSpacing.stackMd),
                          child: Text(
                            widget.products.isEmpty
                                ? 'No products yet.'
                                : 'No products match “$query”.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final product in shown)
                              _PickerTile(
                                product: product,
                                available: widget.available(product),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({required this.product, required this.available});

  final Product product;
  final int available;

  @override
  Widget build(BuildContext context) {
    final enabled = available > 0;
    return ListTile(
      enabled: enabled,
      onTap: () => Navigator.pop(context, product),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: ProductImage(
        url: product.imageUrl,
        size: 40,
        radius: AppRadius.base,
        grayscale: !enabled,
      ),
      title: Text(
        product.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodyLg.copyWith(
          color: enabled ? AppColors.onSurface : AppColors.outline,
        ),
      ),
      subtitle: Text(
        enabled ? '$available available' : 'Out of stock',
        style: AppTypography.bodySm.copyWith(
          color: enabled ? AppColors.onSurfaceVariant : AppColors.error,
        ),
      ),
      trailing: Text(
        formatPeso(product.sellCentavos),
        style: AppTypography.bodyLg.copyWith(
          color: enabled ? AppColors.primary : AppColors.outline,
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.bodyLg.copyWith(
      color: color ?? AppColors.onSurface,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
