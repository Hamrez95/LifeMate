import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'localization.dart';

class LifeMateRuntimeConfigScope extends InheritedWidget {
  const LifeMateRuntimeConfigScope({
    super.key,
    required this.snapshot,
    required super.child,
  });

  final LifeMateRuntimeConfigSnapshot snapshot;

  static LifeMateRuntimeConfigSnapshot? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<LifeMateRuntimeConfigScope>()
          ?.snapshot;

  static LifeMateRuntimeConfigSnapshot of(BuildContext context) {
    final value = maybeOf(context);
    assert(value != null, 'LifeMateRuntimeConfigScope is missing.');
    return value!;
  }

  @override
  bool updateShouldNotify(LifeMateRuntimeConfigScope oldWidget) =>
      oldWidget.snapshot.snapshotVersion != snapshot.snapshotVersion ||
      oldWidget.snapshot.fromCache != snapshot.fromCache;
}

class LifeMateRemoteFeatureGuard extends StatelessWidget {
  const LifeMateRemoteFeatureGuard({
    super.key,
    required this.controlKey,
    required this.child,
    this.fallback = const SizedBox.shrink(),
    this.defaultValue = false,
  });

  final String controlKey;
  final Widget child;
  final Widget fallback;
  final bool defaultValue;

  @override
  Widget build(BuildContext context) {
    final enabled =
        LifeMateRuntimeConfigScope.maybeOf(
          context,
        )?.boolFlag(controlKey, defaultValue: defaultValue) ??
        defaultValue;
    return enabled ? child : fallback;
  }
}

class LifeMateRuntimeConfigGate extends StatefulWidget {
  const LifeMateRuntimeConfigGate({
    super.key,
    required this.child,
    required this.product,
    required this.currentVersion,
    this.beta = false,
    this.client,
    this.onUpdateRequested,
  });

  final Widget child;
  final String product;
  final String currentVersion;
  final bool beta;
  final LifeMateRemoteConfigClient? client;
  final VoidCallback? onUpdateRequested;

  @override
  State<LifeMateRuntimeConfigGate> createState() =>
      _LifeMateRuntimeConfigGateState();
}

class _LifeMateRuntimeConfigGateState extends State<LifeMateRuntimeConfigGate> {
  late LifeMateRemoteConfigClient _client;
  late bool _ownsClient;
  LifeMateRuntimeConfigSnapshot? _snapshot;
  bool _loading = true;
  bool _softDismissed = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _bindClient();
    _load();
  }

  @override
  void didUpdateWidget(covariant LifeMateRuntimeConfigGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.client, widget.client) &&
        oldWidget.product == widget.product &&
        oldWidget.currentVersion == widget.currentVersion &&
        oldWidget.beta == widget.beta) {
      return;
    }
    if (_ownsClient) _client.close();
    _bindClient();
    _snapshot = null;
    _load(forceRefresh: true);
  }

  void _bindClient() {
    _ownsClient = widget.client == null;
    _client =
        widget.client ??
        LifeMateRemoteConfigClient.fromEnvironment(
          product: widget.product,
          currentVersion: widget.currentVersion,
          beta: widget.beta,
        );
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _loading = _snapshot == null;
        _error = null;
      });
    }
    try {
      final snapshot = await _client.load(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _error = null;
        _softDismissed = false;
      });
      unawaited(_client.recordVersionPresence().catchError((_) {}));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (_loading && snapshot == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final effective = snapshot ?? _safeFallback();
    final policyTrusted = effective.isTrustedForUpdatePolicy(DateTime.now());
    if (policyTrusted &&
        effective.updatePolicy.state == LifeMateUpdateState.force) {
      return _ForceUpdate(
        reasonCode: effective.updatePolicy.reasonCode,
        onUpdateRequested: widget.onUpdateRequested,
        onRetry: () => _load(forceRefresh: true),
      );
    }

    final content = LifeMateRuntimeConfigScope(
      snapshot: effective,
      child: widget.child,
    );
    final showOfflineNotice = snapshot == null && _error != null;
    final showSoft =
        policyTrusted &&
        effective.updatePolicy.state == LifeMateUpdateState.soft &&
        !_softDismissed;
    if (!showOfflineNotice && !showSoft) return content;

    return Stack(
      children: [
        content,
        PositionedDirectional(
          start: 12,
          end: 12,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    Icon(
                      showOfflineNotice
                          ? Icons.cloud_off_outlined
                          : Icons.system_update_alt_rounded,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.tr(
                          showOfflineNotice
                              ? 'runtimeConfig.offline'
                              : 'runtimeConfig.softUpdate',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (showOfflineNotice)
                      TextButton(
                        onPressed: () => _load(forceRefresh: true),
                        child: Text(context.tr('common.retry')),
                      )
                    else if (widget.onUpdateRequested != null)
                      TextButton(
                        onPressed: widget.onUpdateRequested,
                        child: Text(context.tr('common.update')),
                      ),
                    if (!showOfflineNotice)
                      IconButton(
                        tooltip: context.tr('common.later'),
                        onPressed: () => setState(() => _softDismissed = true),
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  LifeMateRuntimeConfigSnapshot _safeFallback() {
    final now = DateTime.now().toUtc();
    LifeMateRemoteControl disabled(String key) => LifeMateRemoteControl(
      key: key,
      kind: 'FeatureFlag',
      valueType: 'Boolean',
      value: false,
      definitionVersion: 0,
      source: 'offline_fail_closed',
      ruleVersion: null,
      failClosed: true,
    );
    return LifeMateRuntimeConfigSnapshot(
      product: widget.product,
      platform: 'unknown',
      controls: {
        'client.women_calendar.enabled': disabled(
          'client.women_calendar.enabled',
        ),
        'client.care_pairing.enabled': disabled(
          'client.care_pairing.enabled',
        ),
      },
      updatePolicy: const LifeMateUpdatePolicy(
        state: LifeMateUpdateState.current,
        minimumSupportedVersion: null,
        recommendedVersion: null,
        reasonCode: 'Unavailable',
        messageKey: null,
        policyVersion: 0,
      ),
      snapshotVersion: 'offline-fail-closed',
      fetchedAtUtc: now.subtract(const Duration(days: 2)),
      cacheTtlSeconds: 15,
      fromCache: true,
    );
  }
}

class _ForceUpdate extends StatelessWidget {
  const _ForceUpdate({
    required this.reasonCode,
    required this.onUpdateRequested,
    required this.onRetry,
  });

  final String reasonCode;
  final VoidCallback? onUpdateRequested;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.security_update_warning_rounded, size: 56),
                const SizedBox(height: 18),
                Text(
                  context.tr('runtimeConfig.force.title'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  context.tr(
                    reasonCode == 'Security'
                        ? 'runtimeConfig.force.security'
                        : 'runtimeConfig.force.incompatible',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                if (onUpdateRequested != null)
                  FilledButton.icon(
                    onPressed: onUpdateRequested,
                    icon: const Icon(Icons.system_update_alt_rounded),
                    label: Text(
                      context.tr('runtimeConfig.force.updateLifeMate'),
                    ),
                  ),
                TextButton(
                  onPressed: onRetry,
                  child: Text(context.tr('common.checkAgain')),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
