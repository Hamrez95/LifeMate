import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

class LifeMateRuntimeConfigScope extends InheritedWidget {
  const LifeMateRuntimeConfigScope({
    super.key,
    required this.snapshot,
    required super.child,
  });

  final LifeMateRuntimeConfigSnapshot snapshot;

  static LifeMateRuntimeConfigSnapshot? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LifeMateRuntimeConfigScope>()?.snapshot;

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
    final enabled = LifeMateRuntimeConfigScope.maybeOf(context)?.boolFlag(
          controlKey,
          defaultValue: defaultValue,
        ) ??
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
  State<LifeMateRuntimeConfigGate> createState() => _LifeMateRuntimeConfigGateState();
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
    _load(forceRefresh: true);
  }

  void _bindClient() {
    _ownsClient = widget.client == null;
    _client = widget.client ??
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
      // Presence is operational telemetry and must never block product startup.
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
    if (snapshot == null) {
      return _Unavailable(onRetry: () => _load(forceRefresh: true));
    }
    if (snapshot.updatePolicy.state == LifeMateUpdateState.force) {
      return _ForceUpdate(
        reasonCode: snapshot.updatePolicy.reasonCode,
        onUpdateRequested: widget.onUpdateRequested,
        onRetry: () => _load(forceRefresh: true),
      );
    }

    final content = LifeMateRuntimeConfigScope(
      snapshot: snapshot,
      child: widget.child,
    );
    if (snapshot.updatePolicy.state != LifeMateUpdateState.soft || _softDismissed) {
      return content;
    }
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
                    const Icon(Icons.system_update_alt_rounded),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'A newer LifeMate version is available.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (widget.onUpdateRequested != null)
                      TextButton(
                        onPressed: widget.onUpdateRequested,
                        child: const Text('Update'),
                      ),
                    IconButton(
                      tooltip: 'Later',
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
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'LifeMate could not load its current configuration.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: onRetry, child: const Text('Try again')),
                ],
              ),
            ),
          ),
        ),
      );
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
                    const Text(
                      'Update required',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      reasonCode == 'Security'
                          ? 'This version needs a security update before it can continue.'
                          : 'This version is no longer compatible with the current LifeMate service.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    if (onUpdateRequested != null)
                      FilledButton.icon(
                        onPressed: onUpdateRequested,
                        icon: const Icon(Icons.system_update_alt_rounded),
                        label: const Text('Update LifeMate'),
                      ),
                    TextButton(onPressed: onRetry, child: const Text('Check again')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
