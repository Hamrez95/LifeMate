import 'package:flutter/foundation.dart';

const String todayContractVersion = 'lifemate.today.v1';

enum TodaySeverity { normal, needsAttention, urgent }

enum TodayRankTier { safetyOrOverdue, dueSoon, personalPriority, later }

enum TodayFreshness { live, cached }

enum TodayCompleteness { complete, partial }

enum TodayOwnerKind { currentPerson, companion }

enum TodayItemState { actionable, completed, unavailable }

enum TodayActionKind { moduleRoute, shellRoute, refreshOnly }

enum TodaySourceMode { live, synthetic, unavailable }

@immutable
class TodayOwnerPresentation {
  const TodayOwnerPresentation({
    required this.kind,
    required this.presentationId,
    required this.displayName,
  });

  final TodayOwnerKind kind;
  final String presentationId;
  final String displayName;
}

@immutable
class TodayDisplayContent {
  const TodayDisplayContent({
    required this.title,
    this.subtitle,
    this.timeLabel,
    this.sourceLabel,
  });

  final String title;
  final String? subtitle;
  final String? timeLabel;
  final String? sourceLabel;
}

@immutable
class TodayActionIntent {
  const TodayActionIntent({
    required this.kind,
    required this.routeId,
    this.moduleId,
    this.opaqueTargetId,
    this.requiresOnlineRevalidation = true,
  });

  final TodayActionKind kind;
  final String routeId;
  final String? moduleId;
  final String? opaqueTargetId;
  final bool requiresOnlineRevalidation;
}

@immutable
class TodayItem {
  const TodayItem({
    required this.itemId,
    required this.sourceModuleId,
    required this.owner,
    required this.display,
    required this.severity,
    required this.rankTier,
    required this.stableSortKey,
    this.sortAt,
    this.state = TodayItemState.actionable,
    this.action,
  });

  final String itemId;
  final String sourceModuleId;
  final TodayOwnerPresentation owner;
  final TodayDisplayContent display;
  final TodaySeverity severity;
  final TodayRankTier rankTier;
  final DateTime? sortAt;
  final String stableSortKey;
  final TodayItemState state;
  final TodayActionIntent? action;
}

@immutable
class TodaySnapshot {
  TodaySnapshot({
    required this.generatedAt,
    required List<TodayItem> items,
    this.schemaVersion = todayContractVersion,
    this.freshness = TodayFreshness.live,
    this.completeness = TodayCompleteness.complete,
  }) : items = List.unmodifiable(items) {
    if (schemaVersion != todayContractVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'Unsupported Today contract version',
      );
    }
  }

  final String schemaVersion;
  final DateTime generatedAt;
  final TodayFreshness freshness;
  final TodayCompleteness completeness;
  final List<TodayItem> items;

  List<TodayItem> get sortedItems {
    final result = items.toList(growable: false);
    result.sort(_compareItems);
    return result;
  }

  List<TodayItem> get peekItems => sortedItems
      .where((item) => item.state != TodayItemState.unavailable)
      .take(3)
      .toList(growable: false);

  static int _compareItems(TodayItem left, TodayItem right) {
    final tier = left.rankTier.index.compareTo(right.rankTier.index);
    if (tier != 0) return tier;

    final leftAt = left.sortAt;
    final rightAt = right.sortAt;
    if (leftAt != null && rightAt != null) {
      final time = leftAt.compareTo(rightAt);
      if (time != 0) return time;
    } else if (leftAt != null) {
      return -1;
    } else if (rightAt != null) {
      return 1;
    }

    return left.stableSortKey.compareTo(right.stableSortKey);
  }
}

abstract interface class TodaySnapshotSource {
  TodaySourceMode get mode;

  Future<TodaySnapshot> load();
}

class TodaySourceUnavailable implements Exception {
  const TodaySourceUnavailable();
}

class UnavailableTodaySource implements TodaySnapshotSource {
  const UnavailableTodaySource();

  @override
  TodaySourceMode get mode => TodaySourceMode.unavailable;

  @override
  Future<TodaySnapshot> load() async => throw const TodaySourceUnavailable();
}

/// Explicit preview/test source. Production hosts must inject a reviewed live
/// source rather than treating this static fixture as canonical state.
class SyntheticTodaySource implements TodaySnapshotSource {
  const SyntheticTodaySource(this.snapshot);

  final TodaySnapshot snapshot;

  @override
  TodaySourceMode get mode => TodaySourceMode.synthetic;

  @override
  Future<TodaySnapshot> load() async => snapshot;
}
