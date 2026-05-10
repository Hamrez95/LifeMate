import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // اضافه شده برای بازخورد لمسی (ویبره)
import '../../core/theme/app_style.dart';

class SwipeToConfirm extends StatefulWidget {
  final VoidCallback onConfirm;
  final String text;

  const SwipeToConfirm({Key? key, required this.onConfirm, required this.text})
      : super(key: key);

  @override
  State<SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<SwipeToConfirm>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isConfirmed = false;
  final double _height = 70.0;
  final double _thumbSize = 58.0;

  @override
  void initState() {
    super.initState();
    // استفاده از کنترلر برای کنترل روان انیمیشن‌ها
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details, double maxDrag) {
    if (_isConfirmed) return;
    // چون راست‌چین (RTL) است، کشیدن به چپ مقدار منفی دارد
    _controller.value -= details.delta.dx / maxDrag;
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isConfirmed) return;

    // اگر بیشتر از 70 درصد کشیده شده بود، تایید می‌شود
    if (_controller.value > 0.70) {
      HapticFeedback.heavyImpact(); // ایجاد ویبره ملایم و جذاب
      _controller.forward().then((_) {
        setState(() => _isConfirmed = true);
        // یک مکث کوتاه تا کاربر انیمیشن تیک خوردن را ببیند
        Future.delayed(const Duration(milliseconds: 300), widget.onConfirm);
      });
    } else {
      // اگر کامل کشیده نشده بود، به نرمی برمی‌گردد به اول
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxDrag = constraints.maxWidth - _thumbSize - 12;
        final double currentDrag = _controller.value * maxDrag;

        return Container(
          height: _height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_height / 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowDark
                    .withOpacity(_controller.isCompleted ? 0.2 : 0.5),
                offset: const Offset(0, 8),
                blurRadius: 15,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. ردپای رنگی پشت دکمه (Track Fill)
              Positioned(
                right: 6,
                top: 6,
                bottom: 6,
                width: currentDrag + _thumbSize,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(_height / 2),
                  ),
                ),
              ),

              // 2. متن مرکزی که با کشیدن دست محو می‌شود تا زیر دکمه نرود
              Center(
                child: Opacity(
                  // ضریب 2.5 باعث می‌شود متن سریع‌تر محو شود
                  opacity: (1.0 - (_controller.value * 2.5)).clamp(0.0, 1.0),
                  child: Text(
                    widget.text,
                    style: AppTextStyles.body(context).copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary
                          .withOpacity(0.6), // رنگ ملایم‌تر مشابه iOS
                    ),
                  ),
                ),
              ),

              // 3. دکمه متحرک (Thumb)
              Positioned(
                right: currentDrag + 6,
                child: GestureDetector(
                  onPanUpdate: (details) => _onPanUpdate(details, maxDrag),
                  onPanEnd: (details) => _onPanEnd(details),
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF34D399), Color(0xFF10B981)],
                      ),
                      boxShadow: [
                        // افکت درخشش جذاب بعد از تایید نهایی
                        BoxShadow(
                          color: const Color(0xFF10B981)
                              .withOpacity(_controller.isCompleted ? 0.6 : 0.4),
                          offset: Offset(0, _controller.isCompleted ? 0 : 4),
                          blurRadius: _controller.isCompleted ? 20 : 10,
                          spreadRadius: _controller.isCompleted ? 4 : 0,
                        ),
                      ],
                    ),
                    child: Center(
                      // انیمیشن پرش (Bounce) آیکون
                      child: AnimatedScale(
                        scale: _controller.isCompleted ? 1.2 : 1.0,
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.elasticOut,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          // تغییر آیکون از فلش به تیک
                          child: _controller.isCompleted
                              ? const Icon(Icons.check_rounded,
                                  color: Colors.white,
                                  size: 32,
                                  key: ValueKey('done'))
                              : const Icon(Icons.keyboard_arrow_left_rounded,
                                  color: Colors.white,
                                  size: 36,
                                  key: ValueKey('arrow')),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
