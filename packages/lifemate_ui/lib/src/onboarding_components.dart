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
    final keyboardInset = media.viewInsets.bottom;
    final bottomInset = keyboardAware && keyboardInset > 0 ? keyboardInset : 0.0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: theme.background,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            children: [
              LifeMateOnboardingHeader(
                theme: theme,
                title: title,
                progress: progress,
                progressLabel: progressLabel,
                onBack: onBack,
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
                padding: const EdgeInsets.fromLTRB(
                  LifeMateOnboardingMetrics.screenGutter,
                  12,
                  LifeMateOnboardingMetrics.screenGutter,
                  8,
                ),
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
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: LifeMateOnboardingMetrics.minTouchTarget,
                        ),
                        child: Center(child: secondary),
                      ),
                    ] else
                      const SizedBox(height: 12),
                  ],
                ),
              ),
              if (bottomInset == 0)
                SizedBox(height: media.padding.bottom > 0 ? media.padding.bottom : 12),
            ],
          ),
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
  });

  final LifeMateOnboardingTheme theme;
  final String? title;
  final double? progress;
  final String? progressLabel;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
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
                        fontSize: 16,
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
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: LifeMateOnboardingMetrics.progressHeight,
                value: progress!.clamp(0, 1),
                backgroundColor: theme.border,
                valueColor: AlwaysStoppedAnimation(theme.primary),
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
    final alignment = alignCenter ? CrossAxisAlignment.center : CrossAxisAlignment.stretch;
    final textAlign = alignCenter ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: alignment,
      children: [
        if (icon != null) ...[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: theme.soft, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, color: theme.primary, size: 32),
          ),
          const SizedBox(height: 20),
        ],
        Text(
          title,
          textAlign: textAlign,
          style: TextStyle(
            color: theme.ink,
            fontSize: 22,
            height: 1.4,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 10),
          Text(
            description!,
            textAlign: textAlign,
            style: TextStyle(
              color: theme.muted,
              fontSize: 14,
              height: 1.6,
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
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                  Icon(icon, color: selected ? theme.primary : theme.muted, size: 24),
                  const SizedBox(width: 12),
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
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: theme.muted,
                            fontSize: 13.5,
                            height: 1.45,
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
                    border: Border.all(color: selected ? theme.primary : theme.border, width: 1.5),
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
