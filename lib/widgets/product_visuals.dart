import 'package:flutter/material.dart';

import '../services/product_service.dart';
import '../theme/app_theme.dart';

/// Product pieces shared by the Home search results and the Inventory tab.

/// The design's traffic-light colors and labels for a [StockStatus].
extension StockStatusStyle on StockStatus {
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

/// A product photo in a bordered, rounded frame, or a placeholder icon when
/// there is none or it fails to load.
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
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
