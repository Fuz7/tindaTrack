import 'package:flutter/material.dart';

/// The four-colour Google "G", drawn from the same 24×24 vector paths used in
/// the Stitch sign-in design. Painted directly so the app needs no SVG package.
class GoogleGLogo extends StatelessWidget {
  const GoogleGLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24.0;
    canvas.save();
    canvas.scale(scale);

    final paint = Paint()..isAntiAlias = true;

    canvas.drawPath(_bluePath(), paint..color = _blue);
    canvas.drawPath(_greenPath(), paint..color = _green);
    canvas.drawPath(_yellowPath(), paint..color = _yellow);
    canvas.drawPath(_redPath(), paint..color = _red);

    canvas.restore();
  }

  // M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21
  // 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z
  Path _bluePath() {
    return (_SvgCursor()
          ..moveTo(22.56, 12.25)
          ..curveRel(0, -.78, -.07, -1.53, -.2, -2.25)
          ..horizontalTo(12)
          ..verticalRel(4.26)
          ..horizontalRel(5.92)
          ..curveRel(-.26, 1.37, -1.04, 2.53, -2.21, 3.31)
          ..verticalRel(2.77)
          ..horizontalRel(3.57)
          ..curveRel(2.08, -1.92, 3.28, -4.74, 3.28, -8.09)
          ..close())
        .path;
  }

  // M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71
  // 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z
  Path _greenPath() {
    return (_SvgCursor()
          ..moveTo(12, 23)
          ..curveRel(2.97, 0, 5.46, -.98, 7.28, -2.66)
          ..lineRel(-3.57, -2.77)
          ..curveRel(-.98, .66, -2.23, 1.06, -3.71, 1.06)
          ..curveRel(-2.86, 0, -5.29, -1.93, -6.16, -4.53)
          ..horizontalTo(2.18)
          ..verticalRel(2.84)
          ..curveTo(3.99, 20.53, 7.7, 23, 12, 23)
          ..close())
        .path;
  }

  // M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43
  // 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z
  Path _yellowPath() {
    return (_SvgCursor()
          ..moveTo(5.84, 14.09)
          ..curveRel(-.22, -.66, -.35, -1.36, -.35, -2.09)
          ..smoothRel(.13, -1.43, .35, -2.09)
          ..verticalTo(7.07)
          ..horizontalTo(2.18)
          ..curveTo(1.43, 8.55, 1, 10.22, 1, 12)
          ..smoothRel(.43, 3.45, 1.18, 4.93)
          ..lineRel(2.85, -2.22)
          ..lineRel(.81, -.62)
          ..close())
        .path;
  }

  // M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1
  // 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z
  Path _redPath() {
    return (_SvgCursor()
          ..moveTo(12, 5.38)
          ..curveRel(1.62, 0, 3.06, .56, 4.21, 1.64)
          ..lineRel(3.15, -3.15)
          ..curveTo(17.45, 2.09, 14.97, 1, 12, 1)
          ..curveTo(7.7, 1, 3.99, 3.47, 2.18, 7.07)
          ..lineRel(3.66, 2.84)
          ..curveRel(.87, -2.6, 3.3, -4.53, 6.16, -4.53)
          ..close())
        .path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Minimal SVG path cursor: tracks the current point (and the previous cubic's
/// second control point, for smooth curves) so the path data above can be
/// transcribed command-for-command instead of pre-resolved by hand.
class _SvgCursor {
  final Path path = Path();
  double _x = 0;
  double _y = 0;
  double _ctrlX = 0;
  double _ctrlY = 0;

  /// `M x y`
  void moveTo(double x, double y) {
    _x = x;
    _y = y;
    _ctrlX = x;
    _ctrlY = y;
    path.moveTo(x, y);
  }

  /// `c dx1 dy1 dx2 dy2 dx dy`
  void curveRel(
    double dx1,
    double dy1,
    double dx2,
    double dy2,
    double dx,
    double dy,
  ) {
    path.relativeCubicTo(dx1, dy1, dx2, dy2, dx, dy);
    _ctrlX = _x + dx2;
    _ctrlY = _y + dy2;
    _x += dx;
    _y += dy;
  }

  /// `C x1 y1 x2 y2 x y`
  void curveTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x,
    double y,
  ) {
    path.cubicTo(x1, y1, x2, y2, x, y);
    _ctrlX = x2;
    _ctrlY = y2;
    _x = x;
    _y = y;
  }

  /// `s dx2 dy2 dx dy` — first control point is the reflection of the previous
  /// curve's second control point about the current point.
  void smoothRel(double dx2, double dy2, double dx, double dy) {
    final x1 = 2 * _x - _ctrlX;
    final y1 = 2 * _y - _ctrlY;
    final x2 = _x + dx2;
    final y2 = _y + dy2;
    final x = _x + dx;
    final y = _y + dy;
    path.cubicTo(x1, y1, x2, y2, x, y);
    _ctrlX = x2;
    _ctrlY = y2;
    _x = x;
    _y = y;
  }

  /// `H x`
  void horizontalTo(double x) {
    _x = x;
    _ctrlX = _x;
    _ctrlY = _y;
    path.lineTo(_x, _y);
  }

  /// `h dx`
  void horizontalRel(double dx) => horizontalTo(_x + dx);

  /// `V y`
  void verticalTo(double y) {
    _y = y;
    _ctrlX = _x;
    _ctrlY = _y;
    path.lineTo(_x, _y);
  }

  /// `v dy`
  void verticalRel(double dy) => verticalTo(_y + dy);

  /// `l dx dy`
  void lineRel(double dx, double dy) {
    _x += dx;
    _y += dy;
    _ctrlX = _x;
    _ctrlY = _y;
    path.lineTo(_x, _y);
  }

  /// `z`
  void close() => path.close();
}
