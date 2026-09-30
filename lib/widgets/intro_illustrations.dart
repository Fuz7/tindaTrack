import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The three onboarding illustrations, rebuilt as in-code vector shapes.
///
/// The Stitch designs (`introduction-1/2/3-of-3`) point at remote raster
/// images; drawing them with the design tokens instead keeps the app
/// offline-safe and lets the artwork scale with the layout.

/// Step 1 — "Smart Calculation": an itemised receipt with the calculator
/// overlapping it, mirroring the register-and-basket artwork in the design.
class CalculationIllustration extends StatelessWidget {
  const CalculationIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return _IllustrationFrame(
      child: CustomPaint(painter: _ReceiptCalculatorPainter()),
    );
  }
}

/// Step 2 — "Inventory Control": stocked shelves with one low-stock warning.
class InventoryIllustration extends StatelessWidget {
  const InventoryIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return _IllustrationFrame(
      shape: BoxShape.circle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Smaller unit than the square frames: the shelves have to fit
          // inside the circle's inscribed square, not the full bounds.
          final unit = constraints.maxWidth / 14;
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: unit * 2.6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Shelf(
                  unit: unit,
                  items: [
                    _ShelfItem(
                      width: 1.2,
                      height: 2.0,
                      color: AppColors.primary,
                    ),
                    _ShelfItem(
                      width: 0.9,
                      height: 1.4,
                      color: AppColors.tertiary,
                    ),
                    _ShelfItem(
                      width: 1.5,
                      height: 1.6,
                      color: AppColors.secondary,
                    ),
                  ],
                ),
                SizedBox(height: unit * 1.6),
                _Shelf(
                  unit: unit,
                  items: [
                    _ShelfItem(
                      width: 1.8,
                      height: 1.0,
                      color: AppColors.statusInStock,
                    ),
                    _ShelfItem(
                      width: 1.2,
                      height: 2.2,
                      color: AppColors.surfaceTint,
                    ),
                  ],
                ),
                SizedBox(height: unit * 1.6),
                _Shelf(
                  unit: unit,
                  items: [
                    _ShelfItem(
                      width: 1.1,
                      height: 1.1,
                      color: AppColors.statusLowStock,
                      icon: Icons.priority_high_rounded,
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Step 3 — "Profit Insights": a bar chart with a rising trend line.
class ProfitIllustration extends StatelessWidget {
  const ProfitIllustration({super.key});

  /// (height factor, is highlighted) per bar, left to right.
  static const _bars = <(double, bool)>[
    (0.30, false),
    (0.45, true),
    (0.40, false),
    (0.62, true),
    (0.55, false),
    (0.85, true),
  ];

  @override
  Widget build(BuildContext context) {
    return _IllustrationFrame(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final unit = constraints.maxWidth / 10;
          return Padding(
            padding: EdgeInsets.all(unit * 1.4),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < _bars.length; i++) ...[
                      if (i > 0) SizedBox(width: unit * 0.4),
                      Expanded(
                        child: FractionallySizedBox(
                          heightFactor: _bars[i].$1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: _bars[i].$2
                                  ? AppColors.primary
                                  : AppColors.surfaceContainerHighest,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(AppRadius.sm),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                CustomPaint(
                  painter: _TrendArrowPainter(strokeWidth: unit * 0.4),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Shared 1:1 backdrop: a soft gradient panel with a hairline border, per the
/// `.illustration-container` rule in the Stitch markup.
class _IllustrationFrame extends StatelessWidget {
  const _IllustrationFrame({
    required this.child,
    this.shape = BoxShape.rectangle,
  });

  final Widget child;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: shape,
          borderRadius: shape == BoxShape.rectangle
              ? BorderRadius.circular(AppRadius.md)
              : null,
          border: Border.all(color: AppColors.surfaceBorder),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.surfaceContainerLow,
              AppColors.surfaceContainerHigh,
            ],
          ),
        ),
        child: child,
      ),
    );
  }
}

class _ShelfItem {
  const _ShelfItem({
    required this.width,
    required this.height,
    required this.color,
    this.icon,
  });

  /// Multiples of the layout unit.
  final double width;
  final double height;
  final Color color;
  final IconData? icon;
}

class _Shelf extends StatelessWidget {
  const _Shelf({required this.unit, required this.items});

  final double unit;
  final List<_ShelfItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final item in items)
              Container(
                width: unit * item.width,
                height: unit * item.height,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: item.icon == null
                    ? null
                    : Icon(
                        item.icon,
                        size: unit * 0.7,
                        color: AppColors.onPrimary,
                      ),
              ),
          ],
        ),
        SizedBox(height: unit * 0.2),
        Container(
          height: unit * 0.22,
          decoration: BoxDecoration(
            color: AppColors.outlineVariant,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
        ),
      ],
    );
  }
}

/// Draws the step-1 scene: a torn-off receipt with the calculator resting on
/// top of it. Everything is expressed as a fraction of the canvas so the
/// composition holds at any size.
class _ReceiptCalculatorPainter extends CustomPainter {
  const _ReceiptCalculatorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;

    Paint fill(Color color) => Paint()..color = color;
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    /// A pill in canvas fractions.
    void pill(double l, double t, double w, double h, Color color) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(l * s, t * s, w * s, h * s),
          Radius.circular(h * s / 2),
        ),
        fill(color),
      );
    }

    _paintReceipt(canvas, s, fill, stroke, pill);
    _paintCalculator(canvas, s, fill, stroke);
  }

  void _paintReceipt(
    Canvas canvas,
    double s,
    Paint Function(Color) fill,
    Paint Function(Color, double) stroke,
    void Function(double, double, double, double, Color) pill,
  ) {
    const left = 0.10, right = 0.62, top = 0.08, bottom = 0.78;
    final radius = 0.02 * s;

    // Body: rounded at the top, torn along the bottom edge.
    final path = Path()
      ..moveTo(left * s, (top + 0.02) * s)
      ..arcToPoint(
        Offset((left + 0.02) * s, top * s),
        radius: Radius.circular(radius),
      )
      ..lineTo((right - 0.02) * s, top * s)
      ..arcToPoint(
        Offset(right * s, (top + 0.02) * s),
        radius: Radius.circular(radius),
      )
      ..lineTo(right * s, bottom * s);

    const teeth = 8;
    const toothWidth = (right - left) / teeth;
    for (var i = 0; i < teeth; i++) {
      final x = right - toothWidth * (i + 0.5);
      final y = i.isEven ? bottom + 0.022 : bottom;
      path.lineTo(x * s, y * s);
      path.lineTo((x - toothWidth / 2) * s, bottom * s);
    }
    path
      ..lineTo(left * s, (top + 0.02) * s)
      ..close();

    canvas
      ..drawPath(path, fill(AppColors.surfaceContainerLowest))
      ..drawPath(path, stroke(AppColors.outlineVariant, 1));

    // Header: store name over a subtitle.
    pill(0.16, 0.14, 0.20, 0.035, AppColors.onSurface);
    pill(0.16, 0.195, 0.12, 0.018, AppColors.outlineVariant);

    // Line items — description on the left, amount on the right.
    const itemWidths = [0.22, 0.17, 0.20];
    for (var i = 0; i < itemWidths.length; i++) {
      final y = 0.28 + i * 0.075;
      pill(0.16, y, itemWidths[i], 0.022, AppColors.surfaceContainerHighest);
      pill(0.46, y, 0.10, 0.022, AppColors.outlineVariant);
    }

    // Dashed rule above the total.
    const dashes = 9;
    const dashWidth = (0.56 - 0.16) / (dashes * 2 - 1);
    for (var i = 0; i < dashes; i++) {
      pill(
        0.16 + i * dashWidth * 2,
        0.515,
        dashWidth,
        0.008,
        AppColors.outlineVariant,
      );
    }

    // Total row.
    pill(0.16, 0.55, 0.13, 0.03, AppColors.onSurface);
    pill(0.42, 0.545, 0.14, 0.04, AppColors.primary);
  }

  void _paintCalculator(
    Canvas canvas,
    double s,
    Paint Function(Color) fill,
    Paint Function(Color, double) stroke,
  ) {
    const left = 0.44, top = 0.38, right = 0.92, bottom = 0.94;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTRB(left * s, top * s, right * s, bottom * s),
      Radius.circular(AppRadius.base),
    );

    canvas
      // A gap in the frame colour lifts the calculator off the receipt
      // without resorting to a shadow (the design system has none).
      ..drawRRect(body.inflate(0.018 * s), fill(AppColors.surfaceContainerLow))
      ..drawRRect(body.inflate(0.018 * s), stroke(AppColors.surfaceBorder, 1))
      ..drawRRect(body, fill(AppColors.primary));

    // Display with a right-aligned running total.
    const pad = 0.035;
    final display = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        (left + pad) * s,
        (top + pad) * s,
        (right - pad) * s,
        (top + pad + 0.10) * s,
      ),
      Radius.circular(AppRadius.sm),
    );
    canvas
      ..drawRRect(display, fill(AppColors.primaryFixed))
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            (right - pad - 0.20) * s,
            (top + pad + 0.032) * s,
            0.20 * s,
            0.036 * s,
          ),
          Radius.circular(0.018 * s),
        ),
        fill(AppColors.onPrimaryFixed),
      );

    // 3×3 keypad; the bottom-right key is the accented "total" key.
    const gap = 0.028;
    const keysTop = top + pad + 0.10 + 0.045;
    final keyWidth = (right - left - pad * 2 - gap * 2) / 3;
    final keyHeight = (bottom - pad - keysTop - gap * 2) / 3;

    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        final isAccent = row == 2 && col == 2;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              (left + pad + col * (keyWidth + gap)) * s,
              (keysTop + row * (keyHeight + gap)) * s,
              keyWidth * s,
              keyHeight * s,
            ),
            Radius.circular(AppRadius.sm),
          ),
          fill(isAccent ? AppColors.primaryFixed : AppColors.onPrimary),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ReceiptCalculatorPainter oldDelegate) => false;
}

/// The upward-trending arrow that overlays the profit bars.
class _TrendArrowPainter extends CustomPainter {
  const _TrendArrowPainter({required this.strokeWidth});

  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    // Normalised waypoints (0,0 = top-left) tracing a rising zig-zag.
    const points = <Offset>[
      Offset(0.02, 0.82),
      Offset(0.22, 0.62),
      Offset(0.38, 0.70),
      Offset(0.60, 0.40),
      Offset(0.74, 0.48),
      Offset(0.94, 0.12),
    ];

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = Offset(points[i].dx * size.width, points[i].dy * size.height);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.primaryContainer
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Arrowhead at the last waypoint, aligned with the final segment.
    final tip = Offset(
      points.last.dx * size.width,
      points.last.dy * size.height,
    );
    final prev = Offset(
      points[points.length - 2].dx * size.width,
      points[points.length - 2].dy * size.height,
    );
    final direction = (tip - prev) / (tip - prev).distance;
    final normal = Offset(-direction.dy, direction.dx);
    final headLength = strokeWidth * 3;

    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(
          tip.dx - direction.dx * headLength + normal.dx * headLength * 0.5,
          tip.dy - direction.dy * headLength + normal.dy * headLength * 0.5,
        )
        ..lineTo(
          tip.dx - direction.dx * headLength - normal.dx * headLength * 0.5,
          tip.dy - direction.dy * headLength - normal.dy * headLength * 0.5,
        )
        ..close(),
      Paint()..color = AppColors.primaryContainer,
    );
  }

  @override
  bool shouldRepaint(_TrendArrowPainter oldDelegate) =>
      oldDelegate.strokeWidth != strokeWidth;
}
