import 'package:flutter/material.dart';

import '../services/product_service.dart';
import '../services/store_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart' show formatPeso;

/// The Inventory tab — a Flutter build of the Stitch "Inventory - Product
/// Detail Drawer" design (project 14772063175572299152): search, category
/// chips, SKU and alert counts, the product list, and a bottom drawer with a
/// product's stock and pricing.
///
/// The catalog is read live from Firestore. Adding, editing and restocking are
/// not built yet, so those controls say so when tapped. The design's barcode
/// scan button is left out on purpose: TindaTrack does not use scanning.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.products,
    required this.lowStockThreshold,
  });

  /// Streams rather than a store id so tests can drive the screen without
  /// Firebase; the dashboard passes [ProductService.watch] and
  /// [StoreService.lowStockThresholdOf].
  final Stream<List<Product>> products;
  final Stream<int> lowStockThreshold;

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
    final categories = {
      for (final p in products)
        if (p.category != null) p.category!,
    }.toList()..sort();
    // A category that disappeared (renamed, last product deleted) falls back
    // to All Items instead of showing an empty list with no chip selected.
    final category = categories.contains(_category) ? _category : null;

    final query = _search.text.trim().toLowerCase();
    final visible = products.where((p) {
      if (category != null && p.category != category) return false;
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) ||
          (p.sku?.toLowerCase().contains(query) ?? false);
    }).toList();
    final alerts = products
        .where((p) => p.statusFor(threshold) != StockStatus.inStock)
        .length;

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
              onTap: () => _openDetails(product, threshold),
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
                onPressed: () => _notBuilt(context, 'Adding products'),
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

  void _openDetails(Product product, int threshold) {
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
          _notBuilt(context, 'Editing products');
        },
        onUpdateStock: () {
          Navigator.pop(sheetContext);
          _notBuilt(context, 'Updating stock');
        },
      ),
    );
  }

  static void _notBuilt(BuildContext context, String feature) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$feature is not built yet.')));
  }
}

extension on StockStatus {
  Color get color => switch (this) {
    StockStatus.inStock => AppColors.statusInStock,
    StockStatus.lowStock => AppColors.statusLowStock,
    StockStatus.outOfStock => AppColors.statusOutOfStock,
  };

  String get label => switch (this) {
    StockStatus.inStock => 'IN STOCK',
    StockStatus.lowStock => 'LOW STOCK',
    StockStatus.outOfStock => 'OUT OF STOCK',
  };
}

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
                _ProductImage(
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
                      Text(
                        'Stock: ${_units(product.stock)}',
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

/// A product photo in a bordered, rounded frame, or a placeholder icon when
/// there is none or it fails to load.
class _ProductImage extends StatelessWidget {
  const _ProductImage({
    required this.url,
    required this.size,
    required this.radius,
    this.grayscale = false,
  });

  final String? url;
  final double size;
  final double radius;
  final bool grayscale;

  static const _grayscale = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final placeholder = Icon(
      Icons.inventory_2_outlined,
      size: size * 0.45,
      color: AppColors.outline,
    );
    Widget image = url == null
        ? placeholder
        : Image.network(
            url!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder,
          );
    if (grayscale) image = ColorFiltered(colorFilter: _grayscale, child: image);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: image,
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

class _ProductDrawer extends StatelessWidget {
  const _ProductDrawer({
    required this.product,
    required this.status,
    required this.onEdit,
    required this.onUpdateStock,
  });

  final Product product;
  final StockStatus status;
  final VoidCallback onEdit;
  final VoidCallback onUpdateStock;

  @override
  Widget build(BuildContext context) {
    final margin = product.marginCentavos;
    final marginText = margin == null
        ? '—'
        : product.sellCentavos == 0
        ? formatPeso(margin)
        : '${formatPeso(margin)} '
              '(${(margin / product.sellCentavos * 100).toStringAsFixed(1)}%)';

    return SafeArea(
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
                      _ProductImage(
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
                          value: product.category ?? '—',
                        ),
                      ),
                    ],
                  ),
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onEdit,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
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
                          onPressed: onUpdateStock,
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
