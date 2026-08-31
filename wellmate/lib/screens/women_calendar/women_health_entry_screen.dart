import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';
import 'package:provider/provider.dart';

import 'women_companion_screen.dart';
import 'women_health_activation_v3_screen.dart';

class WomenHealthEntryScreen extends StatefulWidget {
  const WomenHealthEntryScreen({
    super.key,
    this.refreshToken = 0,
    this.onProfileChanged,
  });

  final int refreshToken;
  final Future<void> Function()? onProfileChanged;

  @override
  State<WomenHealthEntryScreen> createState() => _WomenHealthEntryScreenState();
}

class _WomenHealthEntryScreenState extends State<WomenHealthEntryScreen> {
  bool _loading = true;
  bool _enabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WomenHealthEntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load(background: true);
  }

  Future<void> _load({bool background = false}) async {
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled) {
      if (mounted) {
        setState(() {
          _loading = false;
          _enabled = false;
        });
      }
      return;
    }
    if (!background || !_enabled) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final profile = await context
          .read<LifeMateApiClient>()
          .getWomenCalendarProfile();
      if (!mounted) return;
      setState(() {
        _enabled = profile['enabled'] == true;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.tr('women.entry.statusLoadFailed');
      });
    }
  }

  Future<void> _activated() async {
    if (!mounted) return;
    setState(() {
      _enabled = true;
      _loading = false;
      _error = null;
    });
    await widget.onProfileChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final remoteEnabled = LifeMateRuntimeConfigScope.maybeOf(context)?.boolFlag(
          'client.women_calendar.enabled',
          defaultValue: false,
        ) ??
        false;
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled || !remoteEnabled) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility_off_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                context.tr('women.entry.unavailable'),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: Text(context.tr('common.retry')),
              ),
            ],
          ),
        ),
      );
    }
    if (!_enabled) {
      return WomenHealthActivationV3Screen(onActivated: _activated);
    }
    return WomenCompanionScreen(
      refreshToken: widget.refreshToken,
      onProfileChanged: widget.onProfileChanged,
    );
  }
}
