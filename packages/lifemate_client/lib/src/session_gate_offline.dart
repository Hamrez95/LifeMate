import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'durable_lifemate_api_client.dart';
import 'lifemate_api_client.dart';
import 'session_gate_secure.dart' as secure;

typedef DurableAuthenticatedBuilder =
    Widget Function(BuildContext context, LifeMateApiClient apiClient);

/// Thin production wrapper around the existing secure auth/session gate.
///
/// Authentication/bootstrap remains owned by the proven secure gate. Once a
/// session is authenticated, application surfaces receive a durable API client
/// whose idempotent treatment actions survive connectivity loss.
class LifeMateSessionGate extends StatefulWidget {
  const LifeMateSessionGate({
    required this.config,
    required this.appName,
    required this.logoAssetPath,
    required this.authenticatedBuilder,
    super.key,
  });

  final AppConfig config;
  final String appName;
  final String logoAssetPath;
  final DurableAuthenticatedBuilder authenticatedBuilder;

  @override
  State<LifeMateSessionGate> createState() => _LifeMateSessionGateState();
}

class _LifeMateSessionGateState extends State<LifeMateSessionGate>
    with WidgetsBindingObserver {
  late final SupabaseClient _supabase;
  late final DurableLifeMateApiClient _api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _supabase = Supabase.instance.client;
    _api = DurableLifeMateApiClient(
      baseUri: widget.config.apiBaseUri,
      accessToken: () => _supabase.auth.currentSession?.accessToken,
      accountId: () => _supabase.auth.currentUser?.id,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_api.flushPendingMutations());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return secure.LifeMateSessionGate(
      config: widget.config,
      appName: widget.appName,
      logoAssetPath: widget.logoAssetPath,
      authenticatedBuilder: (context, _) {
        // Any successful authenticated rebuild is a cheap reconnect signal.
        unawaited(_api.flushPendingMutations());
        return widget.authenticatedBuilder(context, _api);
      },
    );
  }
}
