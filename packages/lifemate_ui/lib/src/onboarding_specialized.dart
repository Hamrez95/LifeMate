import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_auth/smart_auth.dart';

import 'onboarding_theme.dart';

class LifeMateOtpInput extends StatefulWidget {
  const LifeMateOtpInput({
    super.key,
    required this.theme,
    required this.controller,
    this.length = 6,
    this.enabled = true,
    this.error = false,
    this.onCompleted,
  }) : assert(length > 0);

  final LifeMateOnboardingTheme theme;
  final TextEditingController controller;
  final int length;
  final bool enabled;
  final bool error;
  final ValueChanged<String>? onCompleted;

  @override
  State<LifeMateOtpInput> createState() => _LifeMateOtpInputState();
}

class _LifeMateOtpInputState extends State<LifeMateOtpInput> {
  final FocusNode _focusNode = FocusNode();
  final SmartAuth _smartAuth = SmartAuth.instance;
  bool _consentListening = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _listenForAndroidSms());
  }

  @override
  void didUpdateWidget(covariant LifeMateOtpInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
    if (!oldWidget.enabled && widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _listenForAndroidSms());
    }
  }

  Future<void> _listenForAndroidSms() async {
    if (!mounted ||
        !widget.enabled ||
        _consentListening ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _consentListening = true;
    try {
      final result = await _smartAuth.getSmsWithUserConsentApi();
      if (!mounted || !widget.enabled || !result.hasData) return;
      final rawCode = result.requireData.code;
      if (rawCode == null) return;
      final digits = rawCode.replaceAll(RegExp(r'\D'), '');
      if (digits.length < widget.length) return;
      final code = digits.substring(0, widget.length);
      widget.controller.value = TextEditingValue(
        text: code,
        selection: TextSelection.collapsed(offset: code.length),
      );
    } catch (_) {
      // Android SMS consent is an enhancement only. Native one-time-code
      // autofill and manual entry stay available when Play Services cannot
      // provide a consent result.
    } finally {
      _consentListening = false;
    }
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    final value = widget.controller.text;
    if (value.length == widget.length) widget.onCompleted?.call(value);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _smartAuth.removeUserConsentApiListener();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;
    return Semantics(
      textField: true,
      label: Directionality.of(context) == TextDirection.rtl
          ? 'کد تأیید ${widget.length} رقمی'
          : '${widget.length}-digit verification code',
      value: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? _focusNode.requestFocus : null,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = 6.0;
            final available = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 320.0;
            final calculated =
                (available - gap * (widget.length - 1)) / widget.length;
            final boxWidth = calculated.clamp(36.0, 42.0).toDouble();
            return Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  textDirection: TextDirection.ltr,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.length, (index) {
                    final hasDigit = index < value.length;
                    final active =
                        index == value.length && value.length < widget.length;
                    return Padding(
                      padding: EdgeInsets.only(
                        right: index == widget.length - 1 ? 0 : gap,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: boxWidth,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: widget.theme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: widget.error
                                ? widget.theme.error
                                : active
                                    ? widget.theme.primary
                                    : widget.theme.border,
                            width: active || widget.error ? 1.6 : 1,
                          ),
                        ),
                        child: Text(
                          hasDigit ? value[index] : '',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: widget.theme.ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.01,
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      enabled: widget.enabled,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      textDirection: TextDirection.ltr,
                      maxLength: widget.length,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      autofillHints: const [AutofillHints.oneTimeCode],
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class LifeMateWheelPicker<T> extends StatefulWidget {
  const LifeMateWheelPicker({
    super.key,
    required this.theme,
    required this.items,
    required this.selectedIndex,
    required this.labelBuilder,
    required this.onSelected,
    this.itemExtent = 58,
    this.visibleHeight = 190,
  });

  final LifeMateOnboardingTheme theme;
  final List<T> items;
  final int selectedIndex;
  final String Function(T value) labelBuilder;
  final ValueChanged<int> onSelected;
  final double itemExtent;
  final double visibleHeight;

  @override
  State<LifeMateWheelPicker<T>> createState() => _LifeMateWheelPickerState<T>();
}

class _LifeMateWheelPickerState<T> extends State<LifeMateWheelPicker<T>> {
  late FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(initialItem: widget.selectedIndex);
  }

  @override
  void didUpdateWidget(covariant LifeMateWheelPicker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex &&
        _controller.hasClients &&
        _controller.selectedItem != widget.selectedIndex) {
      _controller.animateToItem(
        widget.selectedIndex,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.visibleHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: widget.itemExtent + 12,
            decoration: BoxDecoration(
              color: widget.theme.surfaceAlt,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: widget.theme.secondary.withValues(alpha: 0.45),
              ),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: _controller,
            itemExtent: widget.itemExtent,
            physics: const FixedExtentScrollPhysics(),
            perspective: 0.002,
            diameterRatio: 1.65,
            onSelectedItemChanged: widget.onSelected,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: widget.items.length,
              builder: (context, index) {
                final selected = index == widget.selectedIndex;
                return Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 140),
                    style: TextStyle(
                      color: selected
                          ? widget.theme.secondary
                          : widget.theme.muted,
                      fontSize: selected ? 22 : 16,
                      fontWeight:
                          selected ? FontWeight.w900 : FontWeight.w600,
                    ),
                    child: Text(widget.labelBuilder(widget.items[index])),
                  ),
                );
              },
            ),
          ),
          IgnorePointer(
            child: Column(
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          widget.theme.background,
                          widget.theme.background.withValues(alpha: 0),
                        ],
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                SizedBox(height: widget.itemExtent),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          widget.theme.background,
                          widget.theme.background.withValues(alpha: 0),
                        ],
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LifeMateConsentScopeCard extends StatelessWidget {
  const LifeMateConsentScopeCard({
    super.key,
    required this.theme,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.icon = Icons.shield_outlined,
    this.sensitive = false,
    this.sensitiveLabel,
  });

  final LifeMateOnboardingTheme theme;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData icon;
  final bool sensitive;
  final String? sensitiveLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: value ? theme.soft : theme.surface,
        borderRadius: BorderRadius.circular(LifeMateOnboardingMetrics.cardRadius),
        border: Border.all(color: value ? theme.primary : theme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration:
                BoxDecoration(color: theme.surfaceAlt, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: sensitive ? theme.secondary : theme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: theme.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (sensitive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.surfaceAlt,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          sensitiveLabel ?? 'Sensitive',
                          style: TextStyle(
                            color: theme.secondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: 13.5,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: theme.primary.withValues(alpha: 0.5),
            activeThumbColor: theme.primary,
          ),
        ],
      ),
    );
  }
}
