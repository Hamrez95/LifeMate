import 'dart:ui';

import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class CocoonStandaloneApp extends StatefulWidget {
  const CocoonStandaloneApp({super.key});

  @override
  State<CocoonStandaloneApp> createState() => _CocoonStandaloneAppState();
}

class _CocoonStandaloneAppState extends State<CocoonStandaloneApp>
    implements CocoonHostContract {
  CocoonEntryState _entryState = CocoonEntryState.runtimeUnavailable;

  @override
  CocoonEntryState get entryState => _entryState;

  @override
  Locale get locale {
    final platform = PlatformDispatcher.instance.locale;
    return platform.languageCode == 'fa' ? const Locale('fa') : const Locale('en');
  }

  @override
  String? get personId => null;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CocoonMate',
      theme: CocoonTheme.light(),
      locale: locale,
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: CocoonMateModule(config: CocoonModuleConfig(host: this)),
    );
  }

  @override
  Future<void> refresh() async {
    // #784 wires canonical Auth/Person/runtime bootstrap. Fail closed until then.
    if (mounted) setState(() => _entryState = CocoonEntryState.runtimeUnavailable);
  }

  @override
  Future<void> openLogin() async {}

  @override
  Future<void> openCommerce() async {}

  @override
  Future<void> beginPregnancySetup() async {}

  @override
  Future<void> openGlobalProfile() async {}

  @override
  void recordSafeEvent(String name) {
    // Host analytics adapter intentionally emits event names only; never PHI.
  }
}
