import 'package:flutter/material.dart';

import 'module_registry.dart';

class ModuleRouteHost extends StatelessWidget {
  const ModuleRouteHost({
    super.key,
    required this.module,
    required this.isPersian,
  });

  final LifeMateModuleDefinition module;
  final bool isPersian;

  String t(String en, String fa) => isPersian ? fa : en;

  @override
  Widget build(BuildContext context) {
    if (module.availability != ModuleAvailability.available ||
        module.pageBuilder == null) {
      return _ModuleStatePage(
        icon: module.icon,
        title: module.label(isPersian: isPersian),
        message: module.availability == ModuleAvailability.locked
            ? t(
                'This module is not available for the current account state.',
                'این ماژول در وضعیت فعلی حساب در دسترس نیست.',
              )
            : t(
                'This module is not mounted in the parent app yet.',
                'این ماژول هنوز در اپ مادر mount نشده است.',
              ),
      );
    }

    try {
      return module.pageBuilder!(context);
    } catch (_) {
      return _ModuleStatePage(
        icon: Icons.error_outline_rounded,
        title: module.label(isPersian: isPersian),
        message: t(
          'This module could not open. The LifeMate shell is still available.',
          'این ماژول باز نشد، اما پوسته LifeMate همچنان در دسترس است.',
        ),
      );
    }
  }
}

class _ModuleStatePage extends StatelessWidget {
  const _ModuleStatePage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Semantics(
                container: true,
                label: title,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 56),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(message, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> openLifeMateModule(
  BuildContext context, {
  required LifeMateModuleDefinition module,
  required bool isPersian,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      settings: RouteSettings(name: module.routeName),
      builder: (_) => ModuleRouteHost(module: module, isPersian: isPersian),
    ),
  );
}
