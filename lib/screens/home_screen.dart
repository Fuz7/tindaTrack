import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The Home (POS) tab — a Flutter build of the Stitch "Home - Calculator"
/// design (project 14772063175572299152): the current entry on top, product
/// search, the calculator keypad, then the active cart and its totals.
///
/// Ringing up is keypad-first: type the price, tap the cart key, and a
/// "Manual Entry" line lands at the top of the cart. Search is wired but there
/// is no product catalog yet, so it has nothing to match against. The cart
/// lives in memory until checkout, which is not built yet either.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// One cart row. Money is whole centavos: doubles would drift (0.1 + 0.2) and
/// a till that is off by a centavo is wrong.
class _CartLine {
  _CartLine({required this.name, required this.unitCentavos});

  final String name;
  final int unitCentavos;
  int quantity = 1;

  int get totalCentavos => unitCentavos * quantity;
}

class _HomeScreenState extends State<HomeScreen> {
  /// Six digits of pesos — ₱999,999 — is far past any sari-sari line item and
  /// keeps the display on one line.
  static const _maxEntryDigits = 6;

  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _lines = <_CartLine>[];

  /// The keypad entry in whole pesos, as typed. Empty means ₱0.00.
  String _entry = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _searchFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  int get _entryCentavos => _entry.isEmpty ? 0 : int.parse(_entry) * 100;
  int get _itemCount => _lines.fold(0, (sum, line) => sum + line.quantity);
  int get _totalCentavos =>
      _lines.fold(0, (sum, line) => sum + line.totalCentavos);

  void _typeDigit(String digit) {
    if (_entry.isEmpty && digit == '0') return; // no leading zeros
    if (_entry.length >= _maxEntryDigits) return;
    setState(() => _entry += digit);
  }

  void _clearEntry() => setState(() => _entry = '');

  /// Newest first, as in the design: the row just rung up is the one the
  /// cashier wants to see.
  void _addEntryToCart() {
    if (_entryCentavos == 0) return;
    setState(() {
      _lines.insert(
        0,
        _CartLine(name: 'Manual Entry', unitCentavos: _entryCentavos),
      );
      _entry = '';
    });
  }

  void _removeLine(_CartLine line) => setState(() => _lines.remove(line));

  /// Clears without a dialog but with an undo — a confirm on every clear slows
  /// the counter down, while a mis-tap mid-sale must still be recoverable.
  void _clearCart() {
    final removed = List.of(_lines);
    setState(_lines.clear);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Cart cleared.'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () {
              if (!mounted) return;
              setState(() => _lines.addAll(removed));
            },
          ),
        ),
      );
  }

  void _completeSale() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Completing a sale is not built yet.')),
      );
  }

  void _closeSearch() {
    _search.clear();
    _searchFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    // While searching, results take the keypad's and cart's place: the
    // keyboard is up, and there is no room for both.
    final searching = _searchFocus.hasFocus || query.isNotEmpty;

    return Column(
      children: [
        if (!searching) _EntryDisplay(centavos: _entryCentavos),
        _SearchBar(
          // Keyed so hiding the display above doesn't rebuild the field and
          // drop its focus mid-typing.
          key: const ValueKey('search'),
          controller: _search,
          focusNode: _searchFocus,
          onClose: _closeSearch,
          searching: searching,
        ),
        Expanded(
          child: searching
              ? _SearchResults(query: query)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final keypad = _Keypad(
                      onDigit: _typeDigit,
                      onClear: _clearEntry,
                      onAdd: _entry.isEmpty ? null : _addEntryToCart,
                    );
                    final minKeypad = _Keypad.heightFor(_Keypad.minRowHeight);
                    final available = constraints.maxHeight;

                    // Too short for a tappable keypad plus a visible cart:
                    // scroll the two together rather than squash either.
                    if (available < minKeypad + _CartSection.minHeight) {
                      return SingleChildScrollView(
                        child: Column(
                          children: [
                            SizedBox(height: minKeypad, child: keypad),
                            _CartSection(
                              lines: _lines,
                              itemCount: _itemCount,
                              onRemove: _removeLine,
                              shrinkWrap: true,
                            ),
                          ],
                        ),
                      );
                    }

                    // Designed at 72px rows; on shorter phones the keypad
                    // gives way first, down to a tappable 44px, and always
                    // leaves the cart room for its header and a row.
                    final keypadHeight = math.min(
                      (available * 0.55).clamp(
                        minKeypad,
                        _Keypad.heightFor(_Keypad.rowHeight),
                      ),
                      available - _CartSection.minHeight,
                    );
                    return Column(
                      children: [
                        SizedBox(height: keypadHeight, child: keypad),
                        Expanded(
                          child: _CartSection(
                            lines: _lines,
                            itemCount: _itemCount,
                            onRemove: _removeLine,
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
        if (!searching)
          _CartFooter(
            totalCentavos: _totalCentavos,
            onClear: _lines.isEmpty ? null : _clearCart,
            onComplete: _lines.isEmpty ? null : _completeSale,
          ),
      ],
    );
  }
}

/// `1,234.50` from centavos.
String formatAmount(int centavos) {
  final whole = (centavos ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+$)'),
    (_) => ',',
  );
  final cents = (centavos % 100).toString().padLeft(2, '0');
  return '$whole.$cents';
}

/// `₱1,234.50` from centavos.
String formatPeso(int centavos) => '₱${formatAmount(centavos)}';

// --- entry & search ---------------------------------------------------------

class _EntryDisplay extends StatelessWidget {
  const _EntryDisplay({required this.centavos});

  final int centavos;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'CURRENT ENTRY',
            style: AppTypography.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '₱',
                  style: AppTypography.headlineLg.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatAmount(centavos),
                  semanticsLabel: 'Current entry ${formatPeso(centavos)}',
                  style: AppTypography.displayPrice.copyWith(
                    color: AppColors.onSurface,
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

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onClose,
    required this.searching,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClose;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: BorderSide(color: color, width: width),
        );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.gutter,
        vertical: 12,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.search,
        style: AppTypography.bodySm.copyWith(color: AppColors.onSurface),
        decoration: InputDecoration(
          hintText: 'Search products...',
          hintStyle: AppTypography.bodySm.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
          prefixIcon: const Icon(
            Icons.search,
            color: AppColors.onSurfaceVariant,
          ),
          // One button both clears and leaves search, so the keypad is
          // always a single tap away.
          suffixIcon: searching
              ? IconButton(
                  tooltip: 'Close search',
                  icon: const Icon(Icons.cancel_outlined),
                  color: AppColors.onSurfaceVariant,
                  onPressed: onClose,
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          filled: true,
          fillColor: AppColors.surfaceContainerLowest,
          border: border(AppColors.outlineVariant),
          enabledBorder: border(AppColors.outlineVariant),
          focusedBorder: border(AppColors.primary, 2),
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = query.isEmpty
        ? (
            Icons.search,
            'Search your products',
            'Type a product name to add it to the cart.',
          )
        : (
            Icons.search_off,
            'No products match “$query”',
            'Products you add in Inventory will show up here.',
          );

    return ColoredBox(
      color: AppColors.surfaceContainerLow,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(icon, size: 40, color: AppColors.outline),
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
      ),
    );
  }
}

// --- keypad -----------------------------------------------------------------

/// 3×4 calculator grid: digits, C (clear entry), 0, and add-to-cart. White
/// keys separated by 1px `surface-border` hairlines.
class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onClear,
    required this.onAdd,
  });

  static const rowHeight = 72.0; // 4.5rem
  static const minRowHeight = 44.0;

  /// Total height for four rows of [row] px, plus the three 1px hairlines.
  static double heightFor(double row) => 4 * row + 3;

  final ValueChanged<String> onDigit;
  final VoidCallback onClear;

  /// Null (disabled) while the entry is ₱0.00.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    Widget digit(String d) => _Key(
      onTap: () => onDigit(d),
      child: Text(d, style: AppTypography.numericKeypad),
    );

    final rows = [
      [digit('7'), digit('8'), digit('9')],
      [digit('4'), digit('5'), digit('6')],
      [digit('1'), digit('2'), digit('3')],
      [
        _Key(
          onTap: onClear,
          tooltip: 'Clear entry',
          child: Text(
            'C',
            style: AppTypography.numericKeypad.copyWith(color: AppColors.error),
          ),
        ),
        digit('0'),
        _Key(
          onTap: onAdd,
          tooltip: 'Add to cart',
          color: AppColors.primaryContainer,
          child: Icon(
            Icons.add_shopping_cart,
            color: onAdd == null
                ? AppColors.onPrimaryContainer.withValues(alpha: 0.5)
                : AppColors.onPrimaryContainer,
          ),
        ),
      ],
    ];

    return ColoredBox(
      color: AppColors.surfaceBorder, // shows through the gaps as hairlines
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: 1),
            Expanded(
              child: Row(
                children: [
                  for (final (j, key) in row.indexed) ...[
                    if (j > 0) const SizedBox(width: 1),
                    Expanded(child: key),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.onTap,
    required this.child,
    this.tooltip,
    this.color = AppColors.surfaceContainerLowest,
  });

  final VoidCallback? onTap;
  final Widget child;
  final String? tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final key = Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        highlightColor: AppColors.surfaceContainerLow,
        child: Center(child: child),
      ),
    );
    return tooltip == null ? key : Tooltip(message: tooltip, child: key);
  }
}

// --- cart -------------------------------------------------------------------

class _CartSection extends StatelessWidget {
  const _CartSection({
    required this.lines,
    required this.itemCount,
    required this.onRemove,
    this.shrinkWrap = false,
  });

  /// Header plus one line — below this the cart can't show anything useful.
  static const minHeight = 50.0 + 73.0;

  final List<_CartLine> lines;
  final int itemCount;
  final ValueChanged<_CartLine> onRemove;

  /// Size to the lines instead of filling (and scrolling within) the parent,
  /// for when an outer scroll view already scrolls the cart with the keypad.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final Widget body = lines.isEmpty
        ? const _EmptyCart()
        : ListView.separated(
            shrinkWrap: shrinkWrap,
            physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: lines.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.outlineVariant),
            itemBuilder: (context, i) => _CartLineTile(
              line: lines[i],
              onRemove: () => onRemove(lines[i]),
            ),
          );

    return ColoredBox(
      color: AppColors.surfaceContainerLowest,
      child: Column(
        mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLow,
              border: Border(
                top: BorderSide(color: AppColors.outlineVariant),
                bottom: BorderSide(color: AppColors.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Active Cart',
                    style: AppTypography.headlineMd.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.base),
                  ),
                  child: Text(
                    '$itemCount ${itemCount == 1 ? 'ITEM' : 'ITEMS'}',
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (shrinkWrap) body else Expanded(child: body),
        ],
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        heightFactor: 1,
        child: Text(
          'Cart is empty. Type a price and tap the cart key.',
          textAlign: TextAlign.center,
          style: AppTypography.bodySm.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({required this.line, required this.onRemove});

  final _CartLine line;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: const Icon(Icons.sell_outlined, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyLg.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  'Qty: ${line.quantity} × ${formatPeso(line.unitCentavos)}',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatPeso(line.totalCentavos),
                style: AppTypography.bodyLg.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  tooltip: 'Remove ${line.name}',
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  color: AppColors.error,
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartFooter extends StatelessWidget {
  const _CartFooter({
    required this.totalCentavos,
    required this.onClear,
    required this.onComplete,
  });

  final int totalCentavos;

  /// Null (disabled) while the cart is empty.
  final VoidCallback? onClear;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        border: Border(top: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'TOTAL AMOUNT',
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatPeso(totalCentavos),
                    style: AppTypography.headlineLg.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onClear,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      backgroundColor: AppColors.outlineVariant,
                      foregroundColor: AppColors.onSurface,
                      disabledBackgroundColor: AppColors.surfaceContainer,
                      textStyle: AppTypography.labelCaps,
                      shape: shape,
                    ),
                    child: const FittedBox(child: Text('CLEAR CART')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: onComplete,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      textStyle: AppTypography.bodyLg.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      shape: shape,
                    ),
                    child: const FittedBox(
                      child: Row(
                        children: [
                          Icon(Icons.check_circle),
                          SizedBox(width: 8),
                          Text('COMPLETE SALE'),
                        ],
                      ),
                    ),
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
