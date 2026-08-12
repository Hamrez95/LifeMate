import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'runtime_locale.dart';

enum LifeMateNoticeType { success, info, warning, error }

abstract final class LifeMateNotice {
  static OverlayEntry? _activeEntry;

  static void show(
    BuildContext context, {
    required String message,
    String? title,
    LifeMateNoticeType type = LifeMateNoticeType.info,
    Duration? duration,
  }) {
    _activeEntry?.remove();
    _activeEntry = null;
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _LifeMateNoticeOverlay(
        message: message,
        title: title,
        type: type,
        duration:
            duration ??
            (type == LifeMateNoticeType.error
                ? const Duration(seconds: 6)
                : const Duration(milliseconds: 3400)),
        onDismissed: () {
          if (entry.mounted) entry.remove();
          if (identical(_activeEntry, entry)) _activeEntry = null;
        },
      ),
    );
    _activeEntry = entry;
    overlay.insert(entry);
  }

  @visibleForTesting
  static void clearForTesting() {
    _activeEntry?.remove();
    _activeEntry = null;
  }
}

class _LifeMateNoticeOverlay extends StatefulWidget {
  const _LifeMateNoticeOverlay({
    required this.message,
    required this.title,
    required this.type,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final String? title;
  final LifeMateNoticeType type;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_LifeMateNoticeOverlay> createState() => _LifeMateNoticeOverlayState();
}

class _LifeMateNoticeOverlayState extends State<_LifeMateNoticeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final media = MediaQuery.maybeOf(context);
      final reduceMotion =
          media?.disableAnimations == true ||
          media?.accessibleNavigation == true;
      if (reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
      _timer = Timer(widget.duration, _dismiss);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        media?.disableAnimations == true || media?.accessibleNavigation == true;
    if (!reduceMotion) await _controller.reverse();
    if (mounted) widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final visual = _NoticeVisual.forType(widget.type);
    final top = MediaQuery.paddingOf(context).top + 10;
    final textDirection = Directionality.of(context);
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 430),
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _controller,
                curve: Curves.easeOut,
              ),
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: Offset(0, -0.22),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: _controller,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: Dismissible(
                  key: ValueKey('${widget.type}-${widget.message}'),
                  direction: DismissDirection.horizontal,
                  onDismissed: (_) => widget.onDismissed(),
                  child: Semantics(
                    liveRegion: true,
                    container: true,
                    label: [widget.title, widget.message]
                        .whereType<String>()
                        .join(
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(fa: '، ', en: ","),
                            en: ",",
                          ),
                        ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: visual.color.withValues(alpha: 0.18),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x16000000),
                                blurRadius: 26,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Directionality(
                            textDirection: textDirection,
                            child: Padding(
                              padding: EdgeInsetsDirectional.fromSTEB(
                                14,
                                12,
                                10,
                                12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: visual.color.withValues(
                                        alpha: 0.12,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      visual.icon,
                                      size: 21,
                                      color: visual.color,
                                    ),
                                  ),
                                  SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (widget.title?.trim().isNotEmpty ==
                                            true)
                                          Text(
                                            widget.title!,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13.5,
                                              color: Color(0xFF253149),
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                        Text(
                                          widget.message,
                                          maxLines: 4,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            height: 1.45,
                                            fontSize: 12.5,
                                            color: Color(0xFF4E596B),
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: LifeMateRuntimeLocale.select(
                                      fa: LifeMateRuntimeLocale.select(
                                        fa: 'بستن',
                                        en: "to close",
                                      ),
                                      en: "to close",
                                    ),
                                    onPressed: _dismiss,
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 19,
                                      color: Color(0xFF7B8492),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeVisual {
  const _NoticeVisual(this.color, this.icon);

  final Color color;
  final IconData icon;

  static _NoticeVisual forType(LifeMateNoticeType type) => switch (type) {
    LifeMateNoticeType.success => const _NoticeVisual(
      Color(0xFF16A978),
      Icons.check_circle_rounded,
    ),
    LifeMateNoticeType.info => const _NoticeVisual(
      Color(0xFF4A90E2),
      Icons.info_rounded,
    ),
    LifeMateNoticeType.warning => const _NoticeVisual(
      Color(0xFFE39A2D),
      Icons.warning_amber_rounded,
    ),
    LifeMateNoticeType.error => const _NoticeVisual(
      Color(0xFFD95D66),
      Icons.error_rounded,
    ),
  };
}
