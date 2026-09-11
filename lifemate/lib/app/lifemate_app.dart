import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../shell/lifemate_shell.dart';

const lifeMateAppVersion = '0.1.0+1';

class LifeMateApp extends StatefulWidget {
  const LifeMateApp({
    super.key,
    this.home,
    this.config,
    this.authInitialized = false,
    this.localeOverride,
  });

  final Widget? home;
  final AppConfig? config;
  final bool authInitialized;
  final Locale? localeOverride;

  @override
  State<LifeMateApp> createState() => _LifeMateAppState();
}

class _LifeMateAppState extends State<LifeMateApp> {
  Locale? _runtimeLocale;

  Locale get _platformLocale {
    final platform = PlatformDispatcher.instance.locale;
    return platform.languageCode == 'fa'
        ? const Locale('fa')
        : const Locale('en');
  }

  Locale get _locale =>
      _runtimeLocale ?? widget.localeOverride ?? _platformLocale;

  void _setLocale(Locale locale) {
    final normalized = locale.languageCode == 'fa'
        ? const Locale('fa')
        : const Locale('en');
    if (_locale == normalized) return;
    setState(() => _runtimeLocale = normalized);
  }

  @override
  Widget build(BuildContext context) {
    final runtimeConfig = widget.config ?? AppConfig.fromEnvironment();
    final locale = _locale;
    final isPersian = locale.languageCode == 'fa';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LifeMate',
      locale: locale,
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _theme(),
      builder: (context, child) => Directionality(
        textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
      home: widget.home ?? _productionHome(runtimeConfig, widget.authInitialized),
    );
  }

  static ThemeData _theme() {
    const seed = Color(0xFF2F8F73);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: const Color(0xFFFFFBF5),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFFFFBF5),
      appBarTheme: const AppBarTheme(centerTitle: false),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
    );
  }

  Widget _productionHome(AppConfig config, bool authInitialized) {
    if (!config.isConfigured) {
      return ConfigurationRequiredScreen(
        appName: 'LifeMate',
        missingValues: config.missingOrInvalidValues,
      );
    }
    if (!authInitialized) {
      return const ConfigurationRequiredScreen(
        appName: 'LifeMate',
        missingValues: ['SUPABASE_INITIALIZATION_FAILED'],
      );
    }

    return LifeMateExperienceGate(
      config: config,
      appName: 'LifeMate',
      releaseVersion: lifeMateAppVersion,
      // #1067 intentionally ships without final brand artwork. Shared auth and
      // blocking states render their built-in fallback icon when this asset is
      // absent. Final visual assets remain owned by the approved design lane.
      logoAssetPath: 'assets/lifemate-logo.png',
      authenticatedBuilder: (context, apiClient) => LifeMateShell(
        apiClient: apiClient,
        onLocaleChanged: _setLocale,
      ),
    );
  }
}
