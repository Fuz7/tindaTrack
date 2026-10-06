import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/product_search.dart';
import '../services/product_service.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import '../widgets/product_visuals.dart';
import 'home_screen.dart' show formatPeso;
import 'product_form_screen.dart';

/// The Inventory tab — a Flutter build of the Stitch "Inventory - Product
/// Detail Drawer" design (project 14772063175572299152): search, category
/// chips, SKU and alert counts, the product list, and a bottom drawer with a
/// product's stock and pricing.
///
/// The catalog comes live from Firestore, through [ProductRepository]. "Add New" and
/// the drawer's "Edit Product" open [ProductFormScreen]; "Update Stock"
/// swaps the drawer's buttons for a stock stepper. The design's barcode
/// scan button
/// is left out on purpose: TindaTrack does not use scanning.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.products,
    required this.lowStockThreshold,
    required this.onSaveProduct,
    required this.onUpdateProduct,
    required this.onDeleteProduct,
    required this.onAdjustStock,
    this.needsAttentionRequest,
  });

  /// Set to true from outside — Analytics' "Restock Now" — to show only the
  /// products that need restocking. The screen clears its other filters,
  /// applies that one, and sets it back to false.
  final ValueNotifier<bool>? needsAttentionRequest;

  /// Streams rather than a store id so tests can drive the screen without
  /// Firebase; the dashboard passes [ProductRepository.watch] and
  /// [StoreService.lowStockThresholdOf].
  final Stream<List<Product>> products;
  final Stream<int> lowStockThreshold;

  /// Saves a new product; the dashboard passes [ProductRepository.add].
  final Future<void> Function(ProductDraft draft) onSaveProduct;

  /// Saves edits to a product, given it as the form opened it; the
  /// dashboard passes [ProductRepository.update].
  final Future<void> Function(Product original, ProductDraft draft)
  onUpdateProduct;

  /// The dashboard passes [ProductRepository.delete].
  final Future<void> Function(String productId) onDeleteProduct;

  /// Sets a product's stock to a counted total, given the product as the
  /// drawer showed it; the dashboard passes [ProductRepository.adjustStock].
  final Future<void> Function(
    Product original,
    int newStock, {
    StockReason? reason,
    String? note,
  })
  onAdjustStock;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _search = TextEditingController();

  /// Null is "All Items".
  String? _category;

  _StockFilter _stock = _StockFilter.all;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    widget.needsAttentionRequest?.addListener(_showNeedsAttention);
    // A request made before this tab was first built.
    _showNeedsAttention();
  }

  @override
  void dispose() {
    widget.needsAttentionRequest?.removeListener(_showNeedsAttention);
    _search.dispose();
    super.dispose();
  }

  void _showNeedsAttention() {
    final request = widget.needsAttentionRequest;
    if (request == null || !request.value) return;
    request.value = false;
    _search.clear();
    setState(() {
      _category = null;
      _stock = _StockFilter.attention;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: widget.lowStockThreshold,
      initialData: StoreDraft.defaultLowStockThreshold,
      builder: (context, thresholdSnapshot) {
        final threshold =
            thresholdSnapshot.data ?? StoreDraft.defaultLowStockThreshold;
        return StreamBuilder<List<Product>>(
          stream: widget.products,
          builder: (context, snapshot) => _buildList(snapshot, threshold),
        );
      },
    );
  }

  Widget _buildList(AsyncSnapshot<List<Product>> snapshot, int threshold) {
    final products = snapshot.data ?? const <Product>[];
    // Products per category, for the filter's ranking and the sheet's counts.
    final counts = <String, int>{};
    for (final p in products) {
      for (final c in p.categories) {
        counts.update(c, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final categories = counts.keys.toList()..sort();
    // A category that disappeared (renamed, last product deleted) falls back
    // to All Items instead of showing an empty list with no chip selected.
    final category = categories.contains(_category) ? _category : null;

    final inCategory = [
      for (final p in products)
        if (category == null || p.categories.contains(category)) p,
    ];
    // The same forgiving search as the Home tab, best matches first.
    final query = _search.text.trim();
    final searched = query.isEmpty
        ? inCategory
        : [for (final m in searchProducts(inCategory, query)) m.product];
    final visible = [
      for (final p in searched)
        if (_stock.matches(p, threshold)) p,
    ];
    // Over the whole catalog, so the sheet's numbers don't shift as other
    // filters change.
    final stockCounts = {
      for (final f in _StockFilter.values)
        f: products.where((p) => f.matches(p, threshold)).length,
    };
    final alerts = stockCounts[_StockFilter.attention]!;

    final Widget listBody;
    if (snapshot.hasError) {
      listBody = const _Message(
        icon: Icons.cloud_off,
        title: 'Could not load products',
        body: 'Check your connection and try again.',
      );
    } else if (!snapshot.hasData) {
      listBody = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (products.isEmpty) {
      listBody = const _Message(
        icon: Icons.inventory_2_outlined,
        title: 'No products yet',
        body: 'Products you add will show up here with their stock.',
      );
    } else if (visible.isEmpty) {
      listBody = const _Message(
        icon: Icons.search_off,
        title: 'No matching products',
        body: 'Try another name, SKU, category or stock filter.',
      );
    } else {
      listBody = Column(
        children: [
          for (final product in visible) ...[
            _ProductCard(
              product: product,
              status: product.statusFor(threshold),
              onTap: () => _openDetails(product, threshold, products),
            ),
            const SizedBox(height: AppSpacing.stackSm),
          ],
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.stackMd,
        AppSpacing.gutter,
        24,
      ),
      children: [
        _SearchField(controller: _search),
        const SizedBox(height: 12),
        _FilterBar(
          counts: counts,
          total: products.length,
          category: category,
          onCategory: (value) => setState(() => _category = value),
          stock: _stock,
          stockCounts: stockCounts,
          onStock: (value) => setState(() => _stock = value),
        ),
        const SizedBox(height: AppSpacing.stackMd),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'TOTAL SKU',
                value: snapshot.hasData ? '${products.length}' : '–',
                background: AppColors.surfaceContainerLow,
                labelColor: AppColors.onSurfaceVariant,
                valueColor: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: 'ALERTS',
                value: snapshot.hasData ? '$alerts' : '–',
                background: AppColors.errorContainer,
                labelColor: AppColors.onErrorContainer,
                valueColor: AppColors.error,
                // A shortcut to exactly what it counts; tap again to clear.
                active: _stock == _StockFilter.attention,
                onTap: () => setState(
                  () => _stock = _stock == _StockFilter.attention
                      ? _StockFilter.all
                      : _StockFilter.attention,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.stackMd),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Inventory',
                  style: AppTypography.headlineMd.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _openAddProduct(categories, {
                  for (final p in products) ?p.sku,
                }),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: Text('ADD NEW', style: AppTypography.labelCaps),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.base),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.stackSm),
        listBody,
      ],
    );
  }

  void _openAddProduct(List<String> categories, Set<String> skus) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductFormScreen(
          onSave: widget.onSaveProduct,
          existingCategories: categories,
          existingSkus: skus,
        ),
      ),
    );
  }

  void _openEditProduct(Product product, List<Product> all) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductFormScreen(
          initial: product,
          onSave: (draft) => widget.onUpdateProduct(product, draft),
          onDelete: () => widget.onDeleteProduct(product.id),
          existingCategories: {for (final p in all) ...p.categories}.toList()
            ..sort(),
          // Its own SKU isn't a clash.
          existingSkus: {
            for (final p in all)
              if (p.id != product.id) ?p.sku,
          },
        ),
      ),
    );
  }

  void _openDetails(Product product, int threshold, List<Product> all) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      barrierColor: const Color(0x66000000), // black/40
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: AppColors.outlineVariant),
      ),
      builder: (sheetContext) => _ProductDrawer(
        product: product,
        status: product.statusFor(threshold),
        // Close first: a snackbar raised under the sheet's barrier would be
        // hidden by it.
        onEdit: () {
          Navigator.pop(sheetContext);
          _openEditProduct(product, all);
        },
        onSaveStock: (update) {
          final count = update.count;
          Navigator.pop(sheetContext);
          final messenger = ScaffoldMessenger.of(context);
          widget
              .onAdjustStock(
                product,
                count,
                reason: update.reason,
                note: update.note,
              )
              .catchError((Object _) {
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        'Could not update “${product.name}”. Try again.',
                      ),
                    ),
                  );
              });
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  '“${product.name}” stock: ${product.stock} → $count'
                  '${update.reason == null ? '' : ' (${update.reason!.label})'}.',
                ),
              ),
            );
        },
      ),
    );
  }
}

/// What the stock updater hands back: the counted total and, for a
/// decrease, why.
typedef _StockUpdate = ({int count, StockReason? reason, String? note});

String _units(int stock) => '$stock ${stock == 1 ? 'unit' : 'units'}';

// --- list -------------------------------------------------------------------

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
      textInputAction: TextInputAction.search,
      style: AppTypography.bodySm.copyWith(color: AppColors.onSurface),
      decoration: InputDecoration(
        hintText: 'Search products...',
        hintStyle: AppTypography.bodySm.copyWith(
          color: AppColors.onSurfaceVariant,
        ),
        prefixIcon: const Icon(Icons.search, color: AppColors.onSurfaceVariant),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                color: AppColors.onSurfaceVariant,
                onPressed: controller.clear,
              ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
        border: border(AppColors.outlineVariant),
        enabledBorder: border(AppColors.outlineVariant),
        focusedBorder: border(AppColors.primaryContainer),
      ),
    );
  }
}

/// Stock-level filters, alongside the category one.
enum _StockFilter {
  all('All stock'),
  attention('Needs attention'),
  low('Low stock'),
  out('Out of stock');

  const _StockFilter(this.label);
  final String label;

  /// "Needs attention" is exactly what the Alerts tile counts; "Out of
  /// stock" includes products with alerts off, since the shelf is empty
  /// either way.
  bool matches(Product p, int threshold) => switch (this) {
    all => true,
    attention => p.needsAlert(threshold),
    low => p.statusFor(threshold) == StockStatus.lowStock,
    out => p.stock <= 0,
  };
}

/// The filter row: an active stock filter as a removable chip, then All
/// Items and as many of the busiest categories as fit, then a pinned
/// Filters button that opens everything.
///
/// The row never scrolls. It measures its chips and shows only those that
/// fit the width, so nothing hides past the edge; the rest are counted on
/// the button and listed in [_FilterSheet]. The selected category always
/// makes the row, whatever its rank.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.counts,
    required this.total,
    required this.category,
    required this.onCategory,
    required this.stock,
    required this.stockCounts,
    required this.onStock,
  });

  /// Products per category.
  final Map<String, int> counts;

  /// All products, for "All Items".
  final int total;
  final String? category;
  final ValueChanged<String?> onCategory;

  final _StockFilter stock;
  final Map<_StockFilter, int> stockCounts;
  final ValueChanged<_StockFilter> onStock;

  static const _chipGap = AppSpacing.stackSm;
  static const _chipPadding = 16.0;

  /// Categories by product count, most first (ties alphabetical).
  List<String> get _ranked => counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });

  Future<void> _openSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _FilterSheet(
        counts: counts,
        total: total,
        category: category,
        onCategory: onCategory,
        stock: stock,
        stockCounts: stockCounts,
        onStock: onStock,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    double chipWidth(String label, {bool removable = false}) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: AppTypography.labelCaps),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      return painter.width +
          2 * _chipPadding +
          (removable ? 20 : 0) + // close icon and its gap
          _chipGap;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final ranked = _ranked;
        // Room for the chips, after the pinned button (≈ icon + "+NN").
        var room = constraints.maxWidth - 72;
        final shown = <String>[];

        // Always shown, in this order: the stock filter, All Items, and the
        // selected category.
        if (stock != _StockFilter.all) {
          room -= chipWidth(stock.label, removable: true);
        }
        room -= chipWidth('All Items');
        if (category != null) {
          shown.add(category!);
          room -= chipWidth(category!);
        }
        for (final c in ranked) {
          if (c == category) continue;
          final w = chipWidth(c);
          if (w > room) break;
          shown.add(c);
          room -= w;
        }
        // Busiest first, with the selected category in its ranked place.
        shown.sort((a, b) => ranked.indexOf(a).compareTo(ranked.indexOf(b)));
        final hidden = counts.length - shown.length;

        return Row(
          children: [
            Expanded(
              // Not scrollable: the chips were picked to fit. This only
              // guards a squeeze (huge text) from an overflow error.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  children: [
                    if (stock != _StockFilter.all)
                      _Pill(
                        label: stock.label,
                        active: true,
                        tone: _PillTone.alert,
                        removeTooltip: 'Clear stock filter',
                        onTap: () => onStock(_StockFilter.all),
                      ),
                    _Pill(
                      label: 'All Items',
                      active: category == null,
                      onTap: () => onCategory(null),
                    ),
                    for (final c in shown)
                      _Pill(
                        label: c,
                        active: c == category,
                        onTap: () => onCategory(c),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: _chipGap),
            Tooltip(
              message: 'Filters',
              child: Material(
                color: AppColors.surfaceContainerLowest,
                shape: const StadiumBorder(
                  side: BorderSide(color: AppColors.outlineVariant),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => _openSheet(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.tune,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        if (hidden > 0) ...[
                          const SizedBox(width: 4),
                          Text(
                            '+$hidden',
                            style: AppTypography.labelCaps.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _PillTone { normal, alert }

/// A filter chip. [removeTooltip] adds a ✕ and marks it as clearing.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.active,
    required this.onTap,
    this.tone = _PillTone.normal,
    this.removeTooltip,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final _PillTone tone;
  final String? removeTooltip;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = !active
        ? (AppColors.surfaceContainer, AppColors.onSurfaceVariant)
        : tone == _PillTone.alert
        ? (AppColors.errorContainer, AppColors.onErrorContainer)
        : (AppColors.primary, AppColors.onPrimary);

    final chip = Padding(
      padding: const EdgeInsets.only(right: _FilterBar._chipGap),
      child: Material(
        color: background,
        elevation: active && tone == _PillTone.normal ? 1 : 0,
        shape: StadiumBorder(
          side: active
              ? BorderSide.none
              : const BorderSide(color: AppColors.outlineVariant),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _FilterBar._chipPadding,
              vertical: 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  style: AppTypography.labelCaps.copyWith(color: foreground),
                ),
                if (removeTooltip != null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.close, size: 16, color: foreground),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return removeTooltip == null
        ? chip
        : Tooltip(message: removeTooltip!, child: chip);
  }
}

/// Every filter: stock level as chips (applied at once, sheet stays open),
/// then every category with its product count, alphabetical, searchable
/// once the list is long (applied and closed).
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.counts,
    required this.total,
    required this.category,
    required this.onCategory,
    required this.stock,
    required this.stockCounts,
    required this.onStock,
  });

  final Map<String, int> counts;
  final int total;
  final String? category;
  final ValueChanged<String?> onCategory;
  final _StockFilter stock;
  final Map<_StockFilter, int> stockCounts;
  final ValueChanged<_StockFilter> onStock;

  /// Past this many categories, a search box earns its space.
  static const searchFrom = 8;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  final _search = TextEditingController();

  /// Mirrors the screen's stock filter, so the sheet's chips update in place.
  late _StockFilter _stock = widget.stock;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final categories =
        widget.counts.keys
            .where((c) => query.isEmpty || c.toLowerCase().contains(query))
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    Widget sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: AppSpacing.stackSm),
      child: Text(
        text,
        style: AppTypography.labelCaps.copyWith(
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );

    Widget tile(String label, String? value, int count) {
      final active = value == widget.category;
      return ListTile(
        onTap: () {
          widget.onCategory(value);
          Navigator.pop(context);
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: Text(
          label,
          style: AppTypography.bodyLg.copyWith(
            color: active ? AppColors.primary : AppColors.onSurface,
            fontWeight: active ? FontWeight.w700 : null,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 24,
              child: active
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
            ),
          ],
        ),
      );
    }

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
                        'Filters',
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
                sectionLabel('STOCK'),
                Wrap(
                  spacing: AppSpacing.stackSm,
                  runSpacing: AppSpacing.stackSm,
                  children: [
                    for (final f in _StockFilter.values)
                      _Pill(
                        label: f == _StockFilter.all
                            ? f.label
                            : '${f.label} (${widget.stockCounts[f] ?? 0})',
                        active: f == _stock,
                        tone: f == _StockFilter.all
                            ? _PillTone.normal
                            : _PillTone.alert,
                        onTap: () {
                          setState(() => _stock = f);
                          widget.onStock(f);
                        },
                      ),
                  ],
                ),
                sectionLabel('CATEGORY'),
                if (widget.counts.length > _FilterSheet.searchFrom) ...[
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Find a category',
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
                ],
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (query.isEmpty) ...[
                        tile('All Items', null, widget.total),
                        const Divider(height: 1),
                      ],
                      for (final c in categories) tile(c, c, widget.counts[c]!),
                      if (categories.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.stackMd),
                          child: Text(
                            'No category matches “${_search.text.trim()}”.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
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

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.background,
    required this.labelColor,
    required this.valueColor,
    this.active = false,
    this.onTap,
  });

  final String label;
  final String value;
  final Color background;
  final Color labelColor;
  final Color valueColor;

  /// Outlined in [valueColor] while the filter it stands for is on.
  final bool active;

  /// Makes the tile a filter shortcut.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.md);
    return Semantics(
      button: onTap != null,
      selected: active,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: active
              ? BorderSide(color: valueColor, width: 2)
              : const BorderSide(color: AppColors.outlineVariant),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTypography.labelCaps.copyWith(
                          color: labelColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: AppTypography.headlineLg.copyWith(
                          color: valueColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    active ? Icons.filter_alt : Icons.filter_alt_outlined,
                    size: 18,
                    color: labelColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.status,
    required this.onTap,
  });

  final Product product;
  final StockStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final out = status == StockStatus.outOfStock;
    return Opacity(
      opacity: out ? 0.8 : 1,
      child: Material(
        color: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          side: const BorderSide(color: AppColors.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.base),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ProductImage(
                  url: product.imageUrl,
                  bytes: product.imageBytes,
                  size: 64,
                  radius: 6,
                  grayscale: out,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyLg.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            if (product.size != null)
                              TextSpan(
                                text: '${product.size} • ',
                                style: const TextStyle(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            TextSpan(text: 'Stock: ${_units(product.stock)}'),
                            if (!product.stockAlerts)
                              const WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: EdgeInsets.only(left: 6),
                                  child: Icon(
                                    Icons.notifications_off_outlined,
                                    size: 14,
                                    color: AppColors.outline,
                                    semanticLabel: 'Low-stock alerts off',
                                  ),
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySm.copyWith(
                          color: status.color,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.stackMd),
                Text(
                  formatPeso(product.sellCentavos),
                  style: AppTypography.headlineMd.copyWith(
                    color: AppColors.primary,
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

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
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
    );
  }
}

// --- detail drawer ----------------------------------------------------------

class _ProductDrawer extends StatefulWidget {
  const _ProductDrawer({
    required this.product,
    required this.status,
    required this.onEdit,
    required this.onSaveStock,
  });

  final Product product;
  final StockStatus status;
  final VoidCallback onEdit;

  /// Saves a new stock count, typed or stepped to in the stock updater.
  final ValueChanged<_StockUpdate> onSaveStock;

  @override
  State<_ProductDrawer> createState() => _ProductDrawerState();
}

class _ProductDrawerState extends State<_ProductDrawer> {
  /// "Update Stock" swaps the action buttons for the design's stock updater.
  bool _updatingStock = false;

  Product get product => widget.product;
  StockStatus get status => widget.status;

  @override
  Widget build(BuildContext context) {
    final margin = product.marginCentavos;
    final marginText = margin == null
        ? '—'
        : product.sellCentavos == 0
        ? formatPeso(margin)
        : '${formatPeso(margin)} '
              '(${(margin / product.sellCentavos * 100).toStringAsFixed(1)}%)';

    // Lift the drawer above the keyboard while a stock count is typed.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Close handle.
              Semantics(
                button: true,
                label: 'Close',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    child: Container(
                      width: 48,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.outlineVariant,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  0,
                  AppSpacing.gutter,
                  32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        ProductImage(
                          url: product.imageUrl,
                          bytes: product.imageBytes,
                          size: 80,
                          radius: AppRadius.base,
                        ),
                        const SizedBox(width: AppSpacing.stackMd),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                style: AppTypography.headlineMd.copyWith(
                                  color: AppColors.onSurface,
                                ),
                              ),
                              if (product.size != null)
                                Text(
                                  product.size!,
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: status.color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.sm,
                                  ),
                                ),
                                child: Text(
                                  status.label,
                                  style: AppTypography.labelCaps.copyWith(
                                    fontSize: 10,
                                    color: status.color,
                                  ),
                                ),
                              ),
                              if (!product.stockAlerts) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.notifications_off_outlined,
                                      size: 14,
                                      color: AppColors.outline,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Low-stock alerts off',
                                      style: AppTypography.bodySm.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _InfoTile(
                            label: 'STOCK',
                            value: _units(product.stock),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _InfoTile(
                            label: 'SKU',
                            value: product.sku ?? '—',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _InfoTile(
                            label: 'CATEGORY',
                            // The tile has room for one; the rest are listed
                            // below the tiles.
                            value: product.mainCategory ?? '—',
                          ),
                        ),
                      ],
                    ),
                    if (product.categories.length > 1) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: AppSpacing.stackSm,
                        runSpacing: AppSpacing.stackSm,
                        children: [
                          for (final (i, category)
                              in product.categories.indexed)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: i == 0
                                    ? AppColors.primaryContainer
                                    : AppColors.surfaceContainer,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
                              ),
                              child: Text(
                                i == 0 ? '$category · MAIN' : category,
                                style: AppTypography.bodySm.copyWith(
                                  color: i == 0
                                      ? AppColors.onPrimaryContainer
                                      : AppColors.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'PRICING DETAILS',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(AppRadius.base),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          _PriceRow(
                            label: 'Buy Price',
                            value: product.buyCentavos == null
                                ? '—'
                                : formatPeso(product.buyCentavos!),
                          ),
                          const Divider(
                            height: 1,
                            color: AppColors.outlineVariant,
                          ),
                          _PriceRow(
                            label: 'Sell Price',
                            value: formatPeso(product.sellCentavos),
                          ),
                          const Divider(
                            height: 1,
                            color: AppColors.outlineVariant,
                          ),
                          _PriceRow(
                            label: 'Margin',
                            value: marginText,
                            highlight: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_updatingStock)
                      _StockUpdater(
                        current: product.stock,
                        onSave: widget.onSaveStock,
                        onCancel: () => setState(() => _updatingStock = false),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: widget.onEdit,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(
                                  color: AppColors.primary,
                                ),
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.base,
                                  ),
                                ),
                              ),
                              child: Text(
                                'EDIT PRODUCT',
                                style: AppTypography.labelCaps,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  setState(() => _updatingStock = true),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.onPrimary,
                                elevation: 1,
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.base,
                                  ),
                                ),
                              ),
                              child: Text(
                                'UPDATE STOCK',
                                style: AppTypography.labelCaps,
                              ),
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
      ),
    );
  }
}

/// The Stitch "Inventory - Direct Stock Update" controls: − / CURRENT STOCK
/// / + over Save Stock, with Cancel back to the drawer's usual buttons.
///
/// The owner sets the count they see on the shelf; only the difference from
/// [current] is saved, so a sale rung up elsewhere meanwhile still counts.
class _StockUpdater extends StatefulWidget {
  const _StockUpdater({
    required this.current,
    required this.onSave,
    required this.onCancel,
  });

  /// The count when the drawer opened. Can be negative after an oversell.
  final int current;
  final ValueChanged<_StockUpdate> onSave;
  final VoidCallback onCancel;

  /// Five digits, as on the add form.
  static const maxStock = 99999;

  @override
  State<_StockUpdater> createState() => _StockUpdaterState();
}

class _StockUpdaterState extends State<_StockUpdater> {
  // A negative count starts the field at 0: it can't be typed, and 0 is
  // the honest floor for a recount.
  late int? _count = math.max(0, widget.current);
  late final _text = TextEditingController(text: '$_count');

  /// Why the count is going down; asked for only then.
  StockReason? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    _note.dispose();
    super.dispose();
  }

  void _step(int by) {
    final next = ((_count ?? 0) + by).clamp(0, _StockUpdater.maxStock).toInt();
    setState(() => _count = next);
    _text.value = TextEditingValue(
      text: '$next',
      selection: TextSelection.collapsed(offset: '$next'.length),
    );
  }

  /// A decrease needs a reason, and "Other" needs a note saying what.
  bool get _reasonComplete =>
      _reason != null &&
      (_reason != StockReason.other || _note.text.trim().isNotEmpty);

  void _save() {
    final count = _count!;
    final decrease = count < widget.current;
    widget.onSave((
      count: count,
      reason: decrease ? _reason : null,
      note: decrease && _note.text.trim().isNotEmpty ? _note.text.trim() : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    final change = count == null ? 0 : count - widget.current;
    final canSave =
        count != null && change != 0 && (change > 0 || _reasonComplete);

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: color, width: width),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.base),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Row(
            children: [
              _SquareStepButton(
                icon: Icons.remove,
                tooltip: 'Remove one',
                onPressed: (count ?? 0) > 0 ? () => _step(-1) : null,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'CURRENT STOCK',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.outline,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: 96,
                      child: TextField(
                        controller: _text,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(5),
                        ],
                        onChanged: (text) =>
                            setState(() => _count = int.tryParse(text)),
                        onSubmitted: (_) {
                          if (canSave) _save();
                        },
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        style: AppTypography.headlineLg.copyWith(
                          color: AppColors.onSurface,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLowest,
                          border: border(AppColors.outlineVariant),
                          enabledBorder: border(AppColors.outlineVariant),
                          focusedBorder: border(AppColors.primary, 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _SquareStepButton(
                icon: Icons.add,
                tooltip: 'Add one',
                onPressed: (count ?? 0) < _StockUpdater.maxStock
                    ? () => _step(1)
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.stackSm),
        // What saving will do, since only the difference is recorded.
        Text(
          count == null
              ? 'Enter the count on the shelf.'
              : change == 0
              ? 'No change from ${widget.current}.'
              : '${change > 0 ? '+' : '−'}${change.abs()} from '
                    '${widget.current}',
          textAlign: TextAlign.center,
          style: AppTypography.bodySm.copyWith(
            color: change > 0
                ? AppColors.statusInStock
                : change < 0
                ? AppColors.actionDestructive
                : AppColors.onSurfaceVariant,
          ),
        ),
        if (change < 0) ...[
          const SizedBox(height: AppSpacing.stackMd),
          _ReasonPicker(
            selected: _reason,
            onSelected: (reason) => setState(() => _reason = reason),
            note: _note,
            onNoteChanged: () => setState(() {}),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: canSave ? _save : null,
          icon: const Icon(Icons.check_circle_outline),
          label: Text('Save Stock', style: AppTypography.bodyLg),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            elevation: 4,
            minimumSize: const Size.fromHeight(AppSpacing.touchTarget),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.base),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.stackSm),
        OutlinedButton(
          onPressed: widget.onCancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.onSurfaceVariant,
            side: const BorderSide(color: AppColors.outlineVariant),
            minimumSize: const Size.fromHeight(AppSpacing.touchTarget),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.base),
            ),
          ),
          child: Text('Cancel', style: AppTypography.bodyLg),
        ),
      ],
    );
  }
}

/// "Reason for decrease": one required pick, and a note — optional, except
/// for Other, where it is the reason.
class _ReasonPicker extends StatelessWidget {
  const _ReasonPicker({
    required this.selected,
    required this.onSelected,
    required this.note,
    required this.onNoteChanged,
  });

  final StockReason? selected;
  final ValueChanged<StockReason> onSelected;
  final TextEditingController note;
  final VoidCallback onNoteChanged;

  @override
  Widget build(BuildContext context) {
    final other = selected == StockReason.other;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          borderSide: BorderSide(color: color, width: width),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'REASON FOR DECREASE',
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.stackSm),
        Wrap(
          spacing: AppSpacing.stackSm,
          runSpacing: AppSpacing.stackSm,
          children: [
            for (final reason in StockReason.values)
              Semantics(
                selected: reason == selected,
                button: true,
                child: Material(
                  color: reason == selected
                      ? AppColors.primaryContainer
                      : AppColors.surfaceContainerLowest,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: reason == selected
                          ? AppColors.primary
                          : AppColors.outlineVariant,
                    ),
                  ),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => onSelected(reason),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        reason.label,
                        style: AppTypography.bodySm.copyWith(
                          color: reason == selected
                              ? AppColors.onPrimaryContainer
                              : AppColors.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: note,
          onChanged: (_) => onNoteChanged(),
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          style: AppTypography.bodySm.copyWith(color: AppColors.onSurface),
          decoration: InputDecoration(
            hintText: other
                ? 'What happened? (required)'
                : 'Note (optional), e.g. dropped by delivery',
            hintStyle: AppTypography.bodySm.copyWith(color: AppColors.outline),
            isDense: true,
            counterText: '',
            filled: true,
            fillColor: AppColors.surfaceContainerLowest,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: border(AppColors.outlineVariant),
            enabledBorder: border(AppColors.outlineVariant),
            focusedBorder: border(AppColors.primary, 2),
          ),
        ),
        if (selected == null || (other && note.text.trim().isEmpty)) ...[
          const SizedBox(height: 4),
          Text(
            selected == null
                ? 'Pick a reason to save a decrease.'
                : 'Add a note for "Other".',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// The updater's white, square-ish − and + keys.
class _SquareStepButton extends StatelessWidget {
  const _SquareStepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      color: AppColors.primary,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(48),
        backgroundColor: AppColors.surfaceContainerLowest,
        disabledBackgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.base),
          side: const BorderSide(color: AppColors.outlineVariant),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.base),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelCaps.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLg.copyWith(color: AppColors.onSurface),
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;

  /// The margin row: tinted, in primary.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: highlight
          ? AppColors.primaryContainer.withValues(alpha: 0.05)
          : null,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySm.copyWith(
                color: highlight
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
                fontWeight: highlight ? FontWeight.w600 : null,
              ),
            ),
          ),
          Text(
            value,
            style: AppTypography.bodySm.copyWith(
              color: highlight ? AppColors.primary : AppColors.onSurface,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
