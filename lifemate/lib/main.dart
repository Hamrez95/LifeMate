import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'app/lifemate_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  var authInitialized = false;
  if (config.isConfigured) {
    try {
      authInitialized = await LifeMateBootstrap.initialize(config);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'lifemate.bootstrap',
          silent: true,
        ),
      );
    }
  }

  runApp(LifeMateApp(config: config, authInitialized: authInitialized));
}
