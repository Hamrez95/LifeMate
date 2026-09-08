part of '../cocoonmate_module.dart';

/// Presentation levels supplied by the host's approved clinical ruleset.
///
/// This renderer never derives a level from symptoms or measurements.
enum CocoonSafetyGuidanceLevel {
  informational,
  attention,
  contactClinician,
  urgent,
}

enum CocoonSafetyGuidanceLoadState {
  loading,
  ready,
  unavailable,
  error,
  offlineCached,
}

/// Fully reviewed, already-localized content supplied by the host.
class CocoonSafetyGuidanceItem {
  const CocoonSafetyGuidanceItem({
    required this.level,
    required this.levelLabel,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.reviewMetadata,
    required this.ruleVersion,
  });

  final CocoonSafetyGuidanceLevel level;
  final String levelLabel;
  final String title;
  final String body;
  final String actionLabel;
  final String reviewMetadata;
  final String ruleVersion;
}

/// Non-clinical interface labels. The host owns localization and wording.
class CocoonSafetyGuidanceCopy {
  const CocoonSafetyGuidanceCopy({
    required this.eyebrow,
    required this.pageTitle,
    required this.pageIntroduction,
    required this.loadingLabel,
    required this.unavailableTitle,
    required this.unavailableBody,
    required this.unavailableActionLabel,
    required this.errorTitle,
    required this.errorBody,
    required this.errorActionLabel,
    required this.offlineCachedLabel,
    required this.reviewedLabel,
    required this.ruleVersionLabel,
  });

  final String eyebrow;
  final String pageTitle;
  final String pageIntroduction;
  final String loadingLabel;
  final String unavailableTitle;
  final String unavailableBody;
  final String unavailableActionLabel;
  final String errorTitle;
  final String errorBody;
  final String errorActionLabel;
  final String offlineCachedLabel;
  final String reviewedLabel;
  final String ruleVersionLabel;
}

class CocoonSafetyGuidanceViewData {
  const CocoonSafetyGuidanceViewData({
    required this.informational,
    required this.attention,
    required this.contactClinician,
    required this.urgent,
    this.cachedAtLabel,
  })  : assert(
          informational.level == CocoonSafetyGuidanceLevel.informational,
        ),
        assert(attention.level == CocoonSafetyGuidanceLevel.attention),
        assert(
          contactClinician.level == CocoonSafetyGuidanceLevel.contactClinician,
        ),
        assert(urgent.level == CocoonSafetyGuidanceLevel.urgent);

  final CocoonSafetyGuidanceItem informational;
  final CocoonSafetyGuidanceItem attention;
  final CocoonSafetyGuidanceItem contactClinician;
  final CocoonSafetyGuidanceItem urgent;
  final String? cachedAtLabel;

  List<CocoonSafetyGuidanceItem> get orderedItems => [
        informational,
        attention,
        contactClinician,
        urgent,
      ];
}

/// UI-only safety guidance renderer.
///
/// The host must inject approved content, its assigned levels, review metadata,
/// and action handling. This widget contains no symptom matching or advice.
class CocoonSafetyGuidanceScreen extends StatelessWidget {
  const CocoonSafetyGuidanceScreen({
    required this.state,
    required this.copy,
    required this.onRetry,
    required this.onGuidanceAction,
    this.data,
    super.key,
  });

  final CocoonSafetyGuidanceLoadState state;
  final CocoonSafetyGuidanceCopy copy;
  final CocoonSafetyGuidanceViewData? data;
  final VoidCallback onRetry;
  final ValueChanged<CocoonSafetyGuidanceItem> onGuidanceAction;

  @override
  Widget build(BuildContext context) => switch (state) {
        CocoonSafetyGuidanceLoadState.loading =>
          _SafetyGuidanceLoading(copy: copy),
        CocoonSafetyGuidanceLoadState.unavailable => CocoonStatePage(
            icon: Icons.shield_outlined,
            eyebrow: copy.eyebrow,
            title: copy.unavailableTitle,
            body: copy.unavailableBody,
            action: copy.unavailableActionLabel,
            onPressed: onRetry,
          ),
        CocoonSafetyGuidanceLoadState.error => CocoonStatePage(
            icon: Icons.sync_problem_outlined,
            eyebrow: copy.eyebrow,
            title: copy.errorTitle,
            body: copy.errorBody,
            action: copy.errorActionLabel,
            onPressed: onRetry,
          ),
        CocoonSafetyGuidanceLoadState.ready when data != null =>
          _SafetyGuidanceContent(
            copy: copy,
            data: data!,
            offlineCached: false,
            onAction: onGuidanceAction,
          ),
        CocoonSafetyGuidanceLoadState.offlineCached when data != null =>
          _SafetyGuidanceContent(
            copy: copy,
            data: data!,
            offlineCached: true,
            onAction: onGuidanceAction,
          ),
        _ => CocoonStatePage(
            icon: Icons.shield_outlined,
            eyebrow: copy.eyebrow,
            title: copy.unavailableTitle,
            body: copy.unavailableBody,
            action: copy.unavailableActionLabel,
            onPressed: onRetry,
          ),
      };
}

class _SafetyGuidanceContent extends StatelessWidget {
  const _SafetyGuidanceContent({
    required this.copy,
    required this.data,
    required this.offlineCached,
    required this.onAction,
  });

  final CocoonSafetyGuidanceCopy copy;
  final CocoonSafetyGuidanceViewData data;
  final bool offlineCached;
  final ValueChanged<CocoonSafetyGuidanceItem> onAction;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const PageStorageKey('cocoon-safety-guidance'),
      slivers: [
        SliverToBoxAdapter(
          child: CocoonPagePadding(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (offlineCached) ...[
                  _SafetyCachedNotice(
                    label: copy.offlineCachedLabel,
                    cachedAtLabel: data.cachedAtLabel,
                  ),
                  const SizedBox(height: 16),
                ],
                _SafetyHero(copy: copy),
                const SizedBox(height: 24),
                for (var index = 0;
                    index < data.orderedItems.length;
                    index++) ...[
                  _SafetyGuidanceSection(
                    item: data.orderedItems[index],
                    reviewedLabel: copy.reviewedLabel,
                    ruleVersionLabel: copy.ruleVersionLabel,
                    onPressed: () => onAction(data.orderedItems[index]),
                  ),
                  if (index != data.orderedItems.length - 1)
                    const SizedBox(height: 14),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SafetyHero extends StatelessWidget {
  const _SafetyHero({required this.copy});

  final CocoonSafetyGuidanceCopy copy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      header: true,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 24, 24, 26),
        decoration: BoxDecoration(
          color: CocoonTheme.sage,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.health_and_safety_outlined,
                color: CocoonTheme.sageStrong,
              ),
            ),
            const SizedBox(height: 26),
            Text(
              copy.eyebrow,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: CocoonTheme.sageStrong,
                  ),
            ),
            const SizedBox(height: 8),
            Text(copy.pageTitle,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(copy.pageIntroduction,
                style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

class _SafetyGuidanceSection extends StatelessWidget {
  const _SafetyGuidanceSection({
    required this.item,
    required this.reviewedLabel,
    required this.ruleVersionLabel,
    required this.onPressed,
  });

  final CocoonSafetyGuidanceItem item;
  final String reviewedLabel;
  final String ruleVersionLabel;
  final VoidCallback onPressed;

  IconData get _icon => switch (item.level) {
        CocoonSafetyGuidanceLevel.informational => Icons.info_outline_rounded,
        CocoonSafetyGuidanceLevel.attention =>
          Icons.notification_important_outlined,
        CocoonSafetyGuidanceLevel.contactClinician =>
          Icons.support_agent_outlined,
        CocoonSafetyGuidanceLevel.urgent => Icons.crisis_alert_outlined,
      };

  Color get _accent => switch (item.level) {
        CocoonSafetyGuidanceLevel.informational => CocoonTheme.skyStrong,
        CocoonSafetyGuidanceLevel.attention => const Color(0xFF7A4B00),
        CocoonSafetyGuidanceLevel.contactClinician => const Color(0xFFA43D34),
        CocoonSafetyGuidanceLevel.urgent => const Color(0xFF8B1E1E),
      };

  Color get _surface => switch (item.level) {
        CocoonSafetyGuidanceLevel.informational => CocoonTheme.sky,
        CocoonSafetyGuidanceLevel.attention => const Color(0xFFFFF3D7),
        CocoonSafetyGuidanceLevel.contactClinician => CocoonTheme.warm,
        CocoonSafetyGuidanceLevel.urgent => const Color(0xFFFFE8E5),
      };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${item.levelLabel}. ${item.title}',
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _accent.withValues(alpha: 0.26)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: _accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(18, 20, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(
                            _icon,
                            color: _accent,
                            semanticLabel: item.levelLabel,
                          ),
                          Container(
                            padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.78),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: _accent.withValues(alpha: 0.32),
                              ),
                            ),
                            child: Text(
                              item.levelLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: _accent),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.body,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 18),
                      _SafetyMetadata(
                        icon: Icons.verified_outlined,
                        label: reviewedLabel,
                        value: item.reviewMetadata,
                      ),
                      const SizedBox(height: 7),
                      _SafetyMetadata(
                        icon: Icons.rule_outlined,
                        label: ruleVersionLabel,
                        value: item.ruleVersion,
                      ),
                      const SizedBox(height: 18),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 168),
                        child: FilledButton.icon(
                          onPressed: onPressed,
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                          ),
                          icon: Icon(_icon),
                          label: Text(item.actionLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SafetyMetadata extends StatelessWidget {
  const _SafetyMetadata({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: CocoonTheme.muted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            '$label: $value',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}

class _SafetyCachedNotice extends StatelessWidget {
  const _SafetyCachedNotice({required this.label, this.cachedAtLabel});

  final String label;
  final String? cachedAtLabel;

  @override
  Widget build(BuildContext context) {
    final details = cachedAtLabel?.trim();
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: CocoonTheme.sky,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: CocoonTheme.skyStrong.withValues(alpha: .2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 20, color: CocoonTheme.skyStrong),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                details == null || details.isEmpty
                    ? label
                    : '$label · $details',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: CocoonTheme.ink,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyGuidanceLoading extends StatelessWidget {
  const _SafetyGuidanceLoading({required this.copy});

  final CocoonSafetyGuidanceCopy copy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: copy.loadingLabel,
      child: ExcludeSemantics(
        child: SingleChildScrollView(
          child: CocoonPagePadding(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 224,
                  decoration: BoxDecoration(
                    color: CocoonTheme.sage,
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                const SizedBox(height: 24),
                for (var index = 0; index < 3; index++) ...[
                  Container(
                    height: 190,
                    decoration: BoxDecoration(
                      color: index.isEven ? CocoonTheme.sky : CocoonTheme.warm,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
