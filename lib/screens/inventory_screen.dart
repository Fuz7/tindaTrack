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
/// The catalog comes from the on-device [ProductRepository]. "Add New" and
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
  });

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

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
    // Every category any product is filed under, main or not.
    final categories = {for (final p in products) ...p.categories}.toList()
      ..sort();
    // A category that disappeared (renamed, last product deleted) falls back
    // to All Items instead of showing an empty list with no chip selected.
    final category = categories.contains(_category) ? _category : null;

    final inCategory = [
      for (final p in products)
        if (category == null || p.categories.contains(category)) p,
    ];
    // The same forgiving search as the Home tab, best matches first.
    final query = _search.text.trim();
    final visible = query.isEmpty
        ? inCategory
        : [for (final m in searchProducts(inCategory, query)) m.product];
    final alerts = products.where((p) => p.needsAlert(threshold)).length;

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
        body: 'Try another name, SKU or category.',
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
        _CategoryChips(
          categories: categories,
          selected: category,
          onSelected: (value) => setState(() => _category = value),
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

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String? value) {
      final active = value == selected;
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.stackSm),
        child: Material(
          color: active ? AppColors.primary : AppColors.surfaceContainer,
          elevation: active ? 1 : 0,
          shape: StadiumBorder(
            side: active
                ? BorderSide.none
                : const BorderSide(color: AppColors.outlineVariant),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => onSelected(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                label,
                style: AppTypography.labelCaps.copyWith(
                  color: active
                      ? AppColors.onPrimary
                      : AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('All Items', null),
          for (final category in categories) chip(category, category),
        ],
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
  });

  final String label;
  final String value;
  final Color background;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.labelCaps.copyWith(color: labelColor),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.headlineLg.copyWith(color: valueColor),
          ),
        ],
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
