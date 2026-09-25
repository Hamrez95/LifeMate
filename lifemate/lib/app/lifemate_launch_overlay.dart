import 'package:flutter/material.dart';

/// Lightweight native launch reveal using the supplied town and logo artwork.
/// The animation stays in Flutter so it can honor Reduce Motion and avoids a
/// video decoder and a second large media asset.
class LifeMateLaunchOverlay extends StatefulWidget {
  const LifeMateLaunchOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<LifeMateLaunchOverlay> createState() => _LifeMateLaunchOverlayState();
}

class _LifeMateLaunchOverlayState extends State<LifeMateLaunchOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2900),
  )..forward();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final t = Curves.easeInOutCubic.transform(_controller.value);
      final showLogo = (t / .72).clamp(0.0, 1.0);
      final leave = ((t - .72) / .28).clamp(0.0, 1.0);
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (leave < 1)
            IgnorePointer(
              child: Opacity(
                opacity: 1 - leave,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/branding/lifemate_launch_city.jpg',
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    ),
                    const ColoredBox(color: Color(0x3310203B)),
                    Align(
                      alignment: Alignment(0, .52 - showLogo * .78),
                      child: Opacity(
                        opacity: showLogo,
                        child: Transform.scale(
                          scale: .56 + showLogo * .44,
                          child: Container(
                            width: 164,
                            height: 164,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xCC0A2752),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF4BD9FF,
                                  ).withValues(alpha: .18 + showLogo * .42),
                                  blurRadius: 24 + showLogo * 28,
                                  spreadRadius: 2 + showLogo * 7,
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/branding/lifemate_logo.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
