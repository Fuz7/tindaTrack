import 'dart:typed_data';

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
///
/// [bytes] is the stored photo, which the store keeps in Firestore and so
/// has on the phone already — it wins over [url], a leftover from when
/// photos were hosted elsewhere.
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    this.url,
    this.bytes,
    required this.size,
    required this.radius,
    this.grayscale = false,
  });

  final String? url;
  final Uint8List? bytes;
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
    Widget image = switch ((bytes, url)) {
      (final Uint8List data, _) => Image.memory(
        data,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // The frame keeps the old photo until the new one is decoded,
        // instead of blinking to the placeholder on every change.
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
      ),
      (_, final String link) => Image.network(
        link,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      ),
      _ => placeholder,
    };
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
