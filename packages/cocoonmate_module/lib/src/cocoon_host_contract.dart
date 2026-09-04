part of '../cocoonmate_module.dart';

enum CocoonEntryState {
  loading,
  unauthenticated,
  runtimeUnavailable,
  notEnrolled,
  notEntitled,
  noPregnancy,
  activePregnancy,
  offline,
}

abstract interface class CocoonHostContract {
  CocoonEntryState get entryState;
  Locale get locale;
  String? get personId;

  Future<void> refresh();
  Future<void> openLogin();
  Future<void> openCommerce();
  Future<void> beginPregnancySetup();
  Future<void> openGlobalProfile();
  void recordSafeEvent(String name);
}

class CocoonModuleConfig {
  const CocoonModuleConfig({
    required this.host,
    this.initialTab = 0,
  });

  final CocoonHostContract host;
  final int initialTab;
}

class CocoonMateModule extends StatelessWidget {
  const CocoonMateModule({
    required this.config,
    super.key,
  });

  final CocoonModuleConfig config;

  @override
  Widget build(BuildContext context) => CocoonShell(config: config);
}
