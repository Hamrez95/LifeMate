import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'module_registry.dart';

class ModuleRouteHost extends StatelessWidget {
  const ModuleRouteHost({
    super.key,
    required this.module,
    required this.isPersian,
    required this.apiClient,
    this.hostActions = const LifeMateModuleHostActions(),
  });

  final LifeMateModuleDefinition module;
  final bool isPersian;
  final LifeMateApiClient? apiClient;
  final LifeMateModuleHostActions hostActions;

  String t(String en, String fa) => isPersian ? fa : en;

  @override
  Widget build(BuildContext context) {
    if (apiClient == null ||
        module.availability != ModuleAvailability.available ||
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
      return module.pageBuilder!(context, apiClient!, hostActions);
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
  required LifeMateApiClient? apiClient,
  LifeMateModuleHostActions hostActions = const LifeMateModuleHostActions(),
}) {
  final reducedMotion = MediaQuery.disableAnimationsOf(context);
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      settings: RouteSettings(name: module.routeName),
      transitionDuration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 620),
      reverseTransitionDuration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 420),
      pageBuilder: (_, _, _) => ModuleRouteHost(
        module: module,
        isPersian: isPersian,
        apiClient: apiClient,
        hostActions: hostActions,
      ),
      transitionsBuilder: (context, animation, _, child) {
        if (reducedMotion) return child;
        final reveal = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return ClipPath(
          clipper: _CampPortalClipper(reveal),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.94, end: 1).animate(reveal),
            child: child,
          ),
        );
      },
    ),
  );
}

/// Reveals a product from the lower middle of the Camp, like entering one of
/// its houses. The temporary clip only runs during route navigation.
class _CampPortalClipper extends CustomClipper<Path> {
  const _CampPortalClipper(this.progress);

  final Animation<double> progress;

  @override
  Path getClip(Size size) {
    final center = Offset(size.width / 2, size.height * 0.72);
    final farthestCorner = <Offset>[
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ].map((point) => (point - center).distance).reduce((a, b) => a > b ? a : b);
    return Path()..addOval(
      Rect.fromCircle(center: center, radius: farthestCorner * progress.value),
    );
  }

  @override
  bool shouldReclip(covariant _CampPortalClipper oldClipper) =>
      oldClipper.progress != progress;
}
