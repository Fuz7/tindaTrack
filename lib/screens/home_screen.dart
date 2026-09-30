import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../services/product_search.dart';
import '../services/product_service.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import '../widgets/product_visuals.dart';

/// The Home (POS) tab — a Flutter build of the Stitch "Home - Calculator"
/// design (project 14772063175572299152): the current entry on top, product
/// search, the calculator keypad, then the active cart and its totals.
///
/// Ringing up is keypad-first: type the price, tap the cart key, and a
/// "Manual Entry" line lands at the top of the cart. Search finds products
/// from the store's inventory by name or SKU; tapping one, or pressing enter
/// for the top match, rings it up at its sell price. The cart lives in memory
/// until checkout, which is not built yet.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.products,
    required this.lowStockThreshold,
  });

  /// Streams rather than a store id so tests can drive the screen without
  /// Firebase; the dashboard passes [ProductRepository.watch] and
  /// [StoreService.lowStockThresholdOf].
  final Stream<List<Product>> products;
  final Stream<int> lowStockThreshold;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// One cart row. Money is whole centavos: doubles would drift (0.1 + 0.2) and
/// a till that is off by a centavo is wrong.
class _CartLine {
  _CartLine({required this.name, required this.unitCentavos, this.productId});

  final String name;
  final int unitCentavos;

  /// The inventory product this line rings up; null for a manual entry.
  final String? productId;
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

  /// The catalog as last heard from [HomeScreen.products]; null until the
  /// first snapshot arrives.
  List<Product>? _products;
  int _lowStockThreshold = StoreDraft.defaultLowStockThreshold;
  late final StreamSubscription<List<Product>> _productsSub;
  late final StreamSubscription<int> _thresholdSub;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _searchFocus.addListener(() => setState(() {}));
    // Held in state rather than a StreamBuilder: the result cards and
    // enter-to-add both need the same latest list.
    _productsSub = widget.products.listen(
      (products) => setState(() => _products = products),
      // Keep the last good list; a failed listen just means search can't
      // see newer products.
      onError: (Object _) => setState(() => _products ??= const []),
    );
    _thresholdSub = widget.lowStockThreshold.listen(
      (threshold) => setState(() => _lowStockThreshold = threshold),
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _productsSub.cancel();
    _thresholdSub.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Rings up [product] at its sell price. A product already in the cart
  /// gains a unit and moves to the top, rather than adding a second row.
  void _addProductToCart(Product product) {
    setState(() {
      final existing = _lines.where((l) => l.productId == product.id);
      final line = existing.isEmpty
          ? _CartLine(
              name: product.displayName,
              unitCentavos: product.sellCentavos,
              productId: product.id,
            )
          : (existing.first..quantity += 1);
      _lines
        ..remove(line)
        ..insert(0, line);
    });
    _closeSearch();
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
    // While searching, the screen stays put behind a dimmed, blurred scrim
    // and the results float over it, as in the "home-search-results-unified"
    // design. Tapping the scrim leaves search.
    final searching = _searchFocus.hasFocus || query.isNotEmpty;
    final matches = searchProducts(_products ?? const [], query);

    return Column(
      children: [
        _SearchScrim(
          visible: searching,
          onTap: _closeSearch,
          child: _EntryDisplay(centavos: _entryCentavos),
        ),
        _SearchBar(
          controller: _search,
          focusNode: _searchFocus,
          onClose: _closeSearch,
          // Enter rings up the top match — the highlighted card.
          onSubmitted: () {
            if (matches.isNotEmpty) _addProductToCart(matches.first.product);
          },
          searching: searching,
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: _SearchScrim(
                  visible: searching,
                  onTap: _closeSearch,
                  child: Column(
                    children: [
                      Expanded(child: _buildKeypadAndCart()),
                      _CartFooter(
                        totalCentavos: _totalCentavos,
                        onClear: _lines.isEmpty ? null : _clearCart,
                        onComplete: _lines.isEmpty ? null : _completeSale,
                      ),
                    ],
                  ),
                ),
              ),
              if (searching)
                _SearchResults(
                  query: query,
                  matches: matches,
                  catalogLoaded: _products != null,
                  catalogEmpty: _products?.isEmpty ?? false,
                  lowStockThreshold: _lowStockThreshold,
                  onSelect: _addProductToCart,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeypadAndCart() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final keypad = _Keypad(
          onDigit: _typeDigit,
          onClear: _clearEntry,
          onAdd: _entry.isEmpty ? null : _addEntryToCart,
        );
        final minKeypad = _Keypad.heightFor(_Keypad.minRowHeight);
        final available = constraints.maxHeight;

        // Too short for a tappable keypad plus a visible cart: scroll the two
        // together rather than squash either.
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

        // Designed at 72px rows; on shorter phones the keypad gives way
        // first, down to a tappable 44px, and always leaves the cart room for
        // its header and a row.
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
    required this.controller,
    required this.focusNode,
    required this.onClose,
    required this.onSubmitted,
    required this.searching,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClose;
  final VoidCallback onSubmitted;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    // Styled after the "home-search-results-unified" design: a 48px, 12px-
    // radius field with a 2px border and a soft drop shadow.
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: color, width: 2),
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: SizedBox(
          height: AppSpacing.touchTarget,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSubmitted(),
            textAlignVertical: TextAlignVertical.center,
            style: AppTypography.bodyLg.copyWith(color: AppColors.onBackground),
            decoration: InputDecoration(
              hintText: 'Search products...',
              hintStyle: AppTypography.bodyLg.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: searching
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
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
              contentPadding: EdgeInsets.zero,
              filled: true,
              fillColor: AppColors.surfaceContainerLowest,
              border: border(AppColors.outlineVariant),
              enabledBorder: border(
                searching ? AppColors.primary : AppColors.outlineVariant,
              ),
              focusedBorder: border(AppColors.primary),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.matches,
    required this.catalogLoaded,
    required this.catalogEmpty,
    required this.lowStockThreshold,
    required this.onSelect,
  });

  final String query;
  final List<ProductMatch> matches;
  final bool catalogLoaded;
  final bool catalogEmpty;
  final int lowStockThreshold;
  final ValueChanged<Product> onSelect;

  @override
  Widget build(BuildContext context) {
    // Result cards float over the scrim, styled like the design's result
    // rows: white, 12px radius, hairline border, small shadow.
    if (matches.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        itemCount: matches.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.stackSm),
        itemBuilder: (context, index) => _SearchResultCard(
          match: matches[index],
          status: matches[index].product.statusFor(lowStockThreshold),
          // The top match is what enter rings up, so it wears the design's
          // emerald outline.
          highlighted: index == 0,
          onTap: () => onSelect(matches[index].product),
        ),
      );
    }

    final (icon, title, body) = query.isEmpty || !catalogLoaded
        ? (
            Icons.search,
            'Search your products',
            'Type a product name or SKU to add it to the cart.',
          )
        : catalogEmpty
        ? (
            Icons.inventory_2_outlined,
            'No products yet',
            'Add products in the Inventory tab to ring them up here.',
          )
        : (
            Icons.search_off,
            'No products match “$query”',
            'Check the spelling, or search by SKU.',
          );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: _ResultFrame(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(AppRadius.base),
              ),
              child: Icon(icon, color: AppColors.outline),
            ),
            const SizedBox(width: AppSpacing.stackMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyLg.copyWith(
                      color: AppColors.onBackground,
                    ),
                  ),
                  Text(
                    body,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
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

/// The white, rounded, shadowed card every search result sits in.
class _ResultFrame extends StatelessWidget {
  const _ResultFrame({
    required this.child,
    this.highlighted = false,
    this.onTap,
  });

  final Widget child;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.md);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: highlighted
              ? const BorderSide(color: AppColors.primary, width: 2)
              : const BorderSide(color: AppColors.outlineVariant),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(12), child: child),
        ),
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.match,
    required this.status,
    required this.highlighted,
    required this.onTap,
  });

  final ProductMatch match;
  final StockStatus status;
  final bool highlighted;
  final VoidCallback onTap;

  Product get product => match.product;

  /// The product name with the matched parts picked out in bold emerald, as
  /// in the design ("**Pi**attos").
  TextSpan _highlightedName() {
    const hit = TextStyle(
      fontWeight: FontWeight.w700,
      color: AppColors.primary,
    );
    final name = product.name;
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in match.highlights) {
      if (start > at) spans.add(TextSpan(text: name.substring(at, start)));
      spans.add(TextSpan(text: name.substring(start, end), style: hit));
      at = end;
    }
    if (at < name.length) spans.add(TextSpan(text: name.substring(at)));
    return TextSpan(
      style: AppTypography.bodyLg.copyWith(color: AppColors.onBackground),
      children: spans,
    );
  }

  @override
  Widget build(BuildContext context) {
    final details = [
      ?product.size,
      ?product.sku,
      '${product.stock} in stock',
    ].join(' • ');

    return Semantics(
      button: true,
      label: 'Add ${product.name} to cart',
      child: _ResultFrame(
        highlighted: highlighted,
        onTap: onTap,
        child: Row(
          children: [
            ProductImage(
              url: product.imageUrl,
              size: 48,
              radius: AppRadius.base,
              grayscale: status == StockStatus.outOfStock,
            ),
            const SizedBox(width: AppSpacing.stackMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    _highlightedName(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.stackSm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatPeso(product.sellCentavos),
                  style: AppTypography.bodyLg.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  status.label,
                  style: AppTypography.labelCaps.copyWith(
                    fontSize: 10,
                    color: status.color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lays a dimmed, lightly blurred scrim over [child] while search is open —
/// the screen stays in view for context but can't be tapped. Tapping the
/// scrim itself calls [onTap].
class _SearchScrim extends StatelessWidget {
  const _SearchScrim({
    required this.visible,
    required this.onTap,
    required this.child,
  });

  final bool visible;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                    // on-background (#171D19) at 40%.
                    child: const ColoredBox(color: Color(0x66171D19)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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
