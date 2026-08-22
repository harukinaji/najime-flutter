import 'package:flutter/material.dart';

class GoogleIcon extends StatelessWidget {
  final double size;

  const GoogleIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: const _GoogleIconPainter(),
    );
  }
}

class _GoogleIconPainter extends CustomPainter {
  const _GoogleIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = w * 0.42;

    final path = Path()
      ..moveTo(cx, cy - r)
      ..arcToPoint(Offset(cx + r, cy), radius: Radius.circular(r))
      ..lineTo(cx + r, cy + r * 0.3)
      ..lineTo(cx - r * 0.1, cy + r * 0.3)
      ..arcToPoint(
        Offset(cx - r * 0.6, cy - r * 0.2),
        radius: Radius.circular(r * 0.6),
        clockwise: false,
      )
      ..arcToPoint(
        Offset(cx, cy - r),
        radius: Radius.circular(r),
        clockwise: false,
      )
      ..close();

    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, redPaint);

    final bluePath = Path()
      ..moveTo(cx, cy - r)
      ..arcToPoint(Offset(cx - r, cy), radius: Radius.circular(r))
      ..lineTo(cx - r, cy + r * 0.3)
      ..lineTo(cx - r * 0.1, cy + r * 0.3)
      ..arcToPoint(
        Offset(cx - r * 0.6, cy - r * 0.2),
        radius: Radius.circular(r * 0.6),
        clockwise: false,
      )
      ..arcToPoint(
        Offset(cx, cy - r),
        radius: Radius.circular(r),
        clockwise: true,
      )
      ..close();

    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawPath(bluePath, bluePaint);

    final yellowPath = Path()
      ..moveTo(cx - r * 0.1, cy + r * 0.3)
      ..lineTo(cx - r, cy + r * 0.3)
      ..arcToPoint(
        Offset(cx - r * 0.5, cy + r * 0.8),
        radius: Radius.circular(r * 0.6),
        clockwise: false,
      )
      ..arcToPoint(
        Offset(cx, cy + r),
        radius: Radius.circular(r * 0.5),
        clockwise: false,
      )
      ..lineTo(cx - r * 0.1, cy + r * 0.3)
      ..close();

    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.fill;
    canvas.drawPath(yellowPath, yellowPaint);

    final greenPath = Path()
      ..moveTo(cx, cy + r)
      ..arcToPoint(
        Offset(cx + r, cy + r * 0.3),
        radius: Radius.circular(r * 0.5),
      )
      ..lineTo(cx + r * 0.3, cy + r * 0.3)
      ..arcToPoint(
        Offset(cx, cy + r),
        radius: Radius.circular(r * 0.35),
        clockwise: false,
      )
      ..close();

    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.fill;
    canvas.drawPath(greenPath, greenPaint);

    final centerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), r * 0.32, centerPaint);

    final innerBluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx - r * 0.02, cy - r * 0.32, r * 0.65, r * 0.64),
      innerBluePaint,
    );

    final coverPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx + r * 0.08, cy - r * 0.32, r * 0.55, r * 0.64),
      coverPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
