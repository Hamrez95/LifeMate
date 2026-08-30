import 'package:flutter/material.dart';

enum LifeMateSubscriptionState { free, trial, premium, expired, inactive }

@immutable
class LifeMateSubscriptionTheme {
  const LifeMateSubscriptionTheme({required this.accent, required this.softSurface});
  final Color accent;
  final Color softSurface;
}

class LifeMateTrialStatus extends StatelessWidget {
  const LifeMateTrialStatus({super.key, required this.remainingDays, required this.theme, this.onTap});
  final int remainingDays;
  final LifeMateSubscriptionTheme theme;
  final VoidCallback? onTap;
  @override Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Semantics(
      button: onTap != null,
      label: 'وضعیت دوره آزمایشی، $remainingDays روز باقی‌مانده',
      child: Material(
        color: theme.softSurface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.hourglass_bottom_rounded, size: 18, color: theme.accent),
              const SizedBox(width: 8),
              Text('$remainingDays روز از دوره آزمایشی باقی مانده', style: Theme.of(context).textTheme.labelLarge),
            ]),
          ),
        ),
      ),
    ),
  );
}

class LifeMateLockedFeatureIndicator extends StatelessWidget {
  const LifeMateLockedFeatureIndicator({super.key, required this.label, required this.theme, this.onTap});
  final String label;
  final LifeMateSubscriptionTheme theme;
  final VoidCallback? onTap;
  @override Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: '$label، نیازمند اشتراک',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(textDirection: TextDirection.rtl, children: [
          Icon(Icons.lock_outline_rounded, color: theme.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(label, textDirection: TextDirection.rtl)),
        ]),
      ),
    ),
  );
}

class LifeMateContextualPaywall extends StatelessWidget {
  const LifeMateContextualPaywall({super.key, required this.title, required this.reason, required this.ctaLabel, required this.theme, required this.onContinue, this.onDismiss});
  final String title;
  final String reason;
  final String ctaLabel;
  final LifeMateSubscriptionTheme theme;
  final VoidCallback onContinue;
  final VoidCallback? onDismiss;
  @override Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Icon(Icons.workspace_premium_outlined, color: theme.accent), const SizedBox(width: 10), Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)), if (onDismiss != null) IconButton(onPressed: onDismiss, tooltip: 'بستن', icon: const Icon(Icons.close_rounded))]),
          const SizedBox(height: 12),
          Text(reason, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 20),
          SizedBox(height: 52, child: FilledButton(onPressed: onContinue, style: FilledButton.styleFrom(backgroundColor: theme.accent), child: Text(ctaLabel))),
        ]),
      ),
    ),
  );
}

class LifeMateOfferCard extends StatelessWidget {
  const LifeMateOfferCard({super.key, required this.title, required this.priceLabel, required this.theme, required this.selected, required this.onSelect, this.compareAtPriceLabel, this.badge});
  final String title;
  final String priceLabel;
  final String? compareAtPriceLabel;
  final String? badge;
  final LifeMateSubscriptionTheme theme;
  final bool selected;
  final VoidCallback onSelect;
  @override Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: selected ? theme.accent : Theme.of(context).dividerColor, width: selected ? 2 : 1), color: selected ? theme.softSurface : null),
        child: Row(textDirection: TextDirection.rtl, children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? theme.accent : null),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, textDirection: TextDirection.rtl, style: Theme.of(context).textTheme.titleMedium), if (badge != null) Text(badge!, textDirection: TextDirection.rtl, style: Theme.of(context).textTheme.labelMedium)])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [if (compareAtPriceLabel != null) Text(compareAtPriceLabel!, style: const TextStyle(decoration: TextDecoration.lineThrough)), Text(priceLabel, style: Theme.of(context).textTheme.titleMedium)]),
        ]),
      ),
    ),
  );
}
