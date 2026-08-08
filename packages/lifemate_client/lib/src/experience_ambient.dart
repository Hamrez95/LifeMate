part of 'lifemate_experience_gate.dart';

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop({
    required this.progress,
    required this.brand,
    this.quieter = false,
  });

  final double progress;
  final _BrandPalette brand;
  final bool quieter;

  @override
  Widget build(BuildContext context) {
    final wave = sin(progress * pi * 2);
    final drift = cos(progress * pi * 2);
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    brand.background,
                    Colors.white,
                    brand.backgroundDeep,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -65 + wave * 15,
            right: -70 + drift * 12,
            child: _BlurOrb(
              size: 245,
              color: brand.secondary.withValues(alpha: quieter ? 0.1 : 0.18),
            ),
          ),
          Positioned(
            bottom: -100 + drift * 18,
            left: -75 + wave * 14,
            child: _BlurOrb(
              size: 280,
              color: brand.primary.withValues(alpha: quieter ? 0.08 : 0.13),
            ),
          ),
          Positioned(
            top: 115 + drift * 18,
            left: 24 + wave * 8,
            child: Icon(
              brand.accentIcon,
              size: 72,
              color: Colors.white.withValues(alpha: quieter ? 0.24 : 0.42),
            ),
          ),
          Positioned(
            top: 82 + wave * 10,
            right: 30,
            child: Icon(
              brand.decorativeIcon,
              size: 90,
              color: brand.primary.withValues(alpha: quieter ? 0.035 : 0.055),
            ),
          ),
          Positioned(
            bottom: 140 + drift * 13,
            right: 30 + wave * 8,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                shape: BoxShape.circle,
                border: Border.all(
                  color: brand.primary.withValues(alpha: 0.18),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 68,
            left: 20,
            right: 20,
            child: Opacity(
              opacity: quieter ? 0.28 : 0.38,
              child: CustomPaint(
                size: const Size(double.infinity, 90),
                painter: _SoftWavePainter(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlurOrb extends StatelessWidget {
  const _BlurOrb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color, blurRadius: 70, spreadRadius: 16)],
      ),
    );
  }
}

class _SoftWavePainter extends CustomPainter {
  const _SoftWavePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height * 0.54)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.15,
        size.width * 0.5,
        size.height * 0.5,
      )
      ..quadraticBezierTo(
        size.width * 0.76,
        size.height * 0.84,
        size.width,
        size.height * 0.32,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SoftWavePainter oldDelegate) =>
      oldDelegate.color != color;
}
