import 'package:flutter/material.dart';

import 'onboarding_theme.dart';

class LifeMateOnboardingScaffold extends StatelessWidget {
  const LifeMateOnboardingScaffold({
    super.key,
    required this.theme,
    required this.body,
    required this.primaryLabel,
    this.onPrimary,
    this.primaryBusy = false,
    this.progress,
    this.progressLabel,
    this.title,
    this.onBack,
    this.secondary,
    this.keyboardAware = false,
  });

  final LifeMateOnboardingTheme theme;
  final Widget body;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryBusy;
  final double? progress;
  final String? progressLabel;
  final String? title;
  final VoidCallback? onBack;
  final Widget? secondary;
  final bool keyboardAware;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardVisible = keyboardAware && media.viewInsets.bottom > 0;
    final compactLayout = keyboardVisible || media.size.height <= 600;
    final actionPadding = compactLayout
        ? const EdgeInsets.fromLTRB(
            LifeMateOnboardingMetrics.screenGutter,
            4,
            LifeMateOnboardingMetrics.screenGutter,
            2,
          )
        : const EdgeInsets.fromLTRB(
            LifeMateOnboardingMetrics.screenGutter,
            12,
            LifeMateOnboardingMetrics.screenGutter,
            8,
          );

    return Scaffold(
      resizeToAvoidBottomInset: keyboardAware,
      backgroundColor: theme.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LifeMateOnboardingHeader(
              theme: theme,
              title: title,
              progress: progress,
              progressLabel: progressLabel,
              onBack: onBack,
              compact: compactLayout,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LifeMateOnboardingMetrics.screenGutter,
                ),
                child: body,
              ),
            ),
            Padding(
              padding: actionPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LifeMatePrimaryOnboardingButton(
                    theme: theme,
                    label: primaryLabel,
                    onPressed: onPrimary,
                    busy: primaryBusy,
                  ),
                  if (secondary != null) ...[
                    SizedBox(height: compactLayout ? 2 : 6),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: compactLayout
                            ? 40
                            : LifeMateOnboardingMetrics.minTouchTarget,
                      ),
                      child: Center(child: secondary),
                    ),
                  ] else
                    SizedBox(height: compactLayout ? 2 : 12),
                ],
              ),
            ),
            if (!compactLayout)
              SizedBox(height: media.padding.bottom > 0 ? media.padding.bottom : 12),
          ],
        ),
      ),
    );
  }
}

class LifeMateOnboardingHeader extends StatelessWidget {
  const LifeMateOnboardingHeader({
    super.key,
    required this.theme,
    this.title,
    this.progress,
    this.progressLabel,
    this.onBack,
    this.compact = false,
  });

  final LifeMateOnboardingTheme theme;
  final String? title;
  final double? progress;
  final String? progressLabel;
  final VoidCallback? onBack;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 2 : 8, 16, compact ? 2 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: compact ? 40 : 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 56),
                    child: Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.ink,
                        fontSize: compact ? 15 : 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                if (onBack != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: IconButton(
                      tooltip: textDirection == TextDirection.rtl ? 'بازگشت' : 'Back',
                      constraints: const BoxConstraints.tightFor(
                        width: LifeMateOnboardingMetrics.minTouchTarget,
                        height: LifeMateOnboardingMetrics.minTouchTarget,
                      ),
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: theme.ink,
                    ),
                  ),
                if (progressLabel != null)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      progressLabel!,
                      style: TextStyle(
                        color: theme.muted,
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (progress != null) ...[
            SizedBox(height: compact ? 2 : 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: LifeMateOnboardingMetrics.progressHeight,
                value: progress!.clamp(0.0, 1.0).toDouble(),
                backgroundColor: theme.border,
                valueColor: AlwaysStoppedAnimation<Color>(theme.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class LifeMateOnboardingQuestion extends StatelessWidget {
  const LifeMateOnboardingQuestion({
    super.key,
    required this.theme,
    required this.title,
    this.description,
    this.icon,
    this.alignCenter = false,
  });

  final LifeMateOnboardingTheme theme;
  final String title;
  final String? description;
  final IconData? icon;
  final bool alignCenter;

  @override
  Widget build(BuildContext context) {
    // A 360x760 device at the accessibility text scale used by the app still
    // needs room for the fixed CTA. Keep the content compact instead of
    // introducing a scroll path that could hide the consent/action controls.
    final compact = MediaQuery.sizeOf(context).height <= 760;
    final alignment = alignCenter ? CrossAxisAlignment.center : CrossAxisAlignment.stretch;
    final textAlign = alignCenter ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: alignment,
      children: [
        if (icon != null) ...[
          Container(
            width: compact ? 56 : 72,
            height: compact ? 56 : 72,
            decoration: BoxDecoration(color: theme.soft, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, color: theme.primary, size: compact ? 26 : 32),
          ),
          SizedBox(height: compact ? 10 : 20),
        ],
        Text(
          title,
          textAlign: textAlign,
          style: TextStyle(
            color: theme.ink,
            fontSize: compact ? 19 : 22,
            height: compact ? 1.25 : 1.4,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (description != null) ...[
          SizedBox(height: compact ? 6 : 10),
          Text(
            description!,
            textAlign: textAlign,
            style: TextStyle(
              color: theme.muted,
              fontSize: compact ? 13 : 14,
              height: compact ? 1.4 : 1.6,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class LifeMateOnboardingOptionCard extends StatelessWidget {
  const LifeMateOnboardingOptionCard({
    super.key,
    required this.theme,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.enabled = true,
  });

  final LifeMateOnboardingTheme theme;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height <= 760;
    final foreground = enabled ? theme.ink : theme.muted.withValues(alpha: 0.65);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Material(
        color: selected ? theme.soft : theme.surface,
        borderRadius: BorderRadius.circular(LifeMateOnboardingMetrics.cardRadius),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(LifeMateOnboardingMetrics.cardRadius),
          child: Container(
            constraints: BoxConstraints(minHeight: compact ? 64 : 76),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 10 : 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LifeMateOnboardingMetrics.cardRadius),
              border: Border.all(
                color: selected ? theme.primary : theme.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: selected ? theme.primary : theme.muted, size: compact ? 22 : 24),
                  SizedBox(width: compact ? 10 : 12),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: foreground,
                          fontSize: compact ? 14.5 : 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null) ...[
                          SizedBox(height: compact ? 2 : 4),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: theme.muted,
                            fontSize: compact ? 12.5 : 13.5,
                            height: compact ? 1.25 : 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? theme.primary : Colors.transparent,
                    border: Border.all(
                      color: selected ? theme.primary : theme.border,
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LifeMateOnboardingTextField extends StatelessWidget {
  const LifeMateOnboardingTextField({
    super.key,
    required this.theme,
    required this.controller,
    required this.label,
    this.hintText,
    this.errorText,
    this.keyboardType,
    this.textInputAction,
    this.textDirection,
    this.onSubmitted,
    this.autofillHints,
    this.enabled = true,
    this.obscureText = false,
    this.prefixIcon,
    this.suffix,
  });

  final LifeMateOnboardingTheme theme;
  final TextEditingController controller;
  final String label;
  final String? hintText;
  final String? errorText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextDirection? textDirection;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final bool obscureText;
  final IconData? prefixIcon;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: LifeMateOnboardingMetrics.inputHeight,
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            textDirection: textDirection,
            onSubmitted: onSubmitted,
            autofillHints: autofillHints,
            obscureText: obscureText,
            decoration: InputDecoration(
              hintText: hintText,
              filled: true,
              fillColor: theme.surface,
              prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, color: theme.muted),
              suffixIcon: suffix,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(LifeMateOnboardingMetrics.controlRadius),
                borderSide: BorderSide(color: errorText == null ? theme.border : theme.error),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(LifeMateOnboardingMetrics.controlRadius),
                borderSide: BorderSide(color: errorText == null ? theme.primary : theme.error, width: 1.6),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(LifeMateOnboardingMetrics.controlRadius),
                borderSide: BorderSide(color: theme.border),
              ),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, color: theme.error, size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  errorText!,
                  style: TextStyle(
                    color: theme.error,
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class LifeMatePrimaryOnboardingButton extends StatelessWidget {
  const LifeMatePrimaryOnboardingButton({
    super.key,
    required this.theme,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final LifeMateOnboardingTheme theme;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: LifeMateOnboardingMetrics.ctaHeight,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: theme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: theme.border,
          disabledForegroundColor: theme.muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LifeMateOnboardingMetrics.controlRadius),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        child: busy
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : Text(label),
      ),
    );
  }
}
