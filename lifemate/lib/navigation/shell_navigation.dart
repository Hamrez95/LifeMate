import 'package:flutter/material.dart';

enum ShellDestination {
  home(id: 'home', path: '/home'),
  today(id: 'today', path: '/today'),
  journey(id: 'journey', path: '/journey'),
  circle(id: 'circle', path: '/circle'),
  you(id: 'you', path: '/you');

  const ShellDestination({required this.id, required this.path});

  final String id;
  final String path;
}

const shellDestinationOrder = <ShellDestination>[
  ShellDestination.home,
  ShellDestination.today,
  ShellDestination.journey,
  ShellDestination.circle,
  ShellDestination.you,
];

class ShellNavigationIntent {
  const ShellNavigationIntent({
    required this.path,
    this.destination,
    this.moduleId,
    this.resourceId,
  });

  final String path;
  final ShellDestination? destination;
  final String? moduleId;
  final String? resourceId;
}

const _allowedOpaqueQueryKeys = {'resourceId', 'v'};
const _blockedSensitiveQueryKeys = {
  'name',
  'personName',
  'medication',
  'diagnosis',
  'pregnancy',
  'glucose',
  'bloodPressure',
  'note',
};

ShellNavigationIntent? normalizeShellUri(Uri uri) {
  if (uri.queryParameters.keys.any(_blockedSensitiveQueryKeys.contains)) {
    return null;
  }
  if (uri.queryParameters.keys.any(
    (key) => !_allowedOpaqueQueryKeys.contains(key),
  )) {
    return null;
  }

  final path = _normalizePath(uri.path);
  for (final destination in shellDestinationOrder) {
    if (path == destination.path) {
      return ShellNavigationIntent(path: path, destination: destination);
    }
  }

  if (path == '/notifications' ||
      path == '/support' ||
      path == '/you/profile' ||
      path == '/you/settings' ||
      path == '/you/subscription' ||
      path == '/you/privacy' ||
      path == '/you/accessibility') {
    return ShellNavigationIntent(
      path: path,
      resourceId: _opaqueResourceId(uri),
    );
  }

  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.length >= 2 && segments.first == 'apps') {
    final moduleId = segments[1].trim();
    if (!_isSafeStableId(moduleId)) return null;
    return ShellNavigationIntent(
      path: path,
      moduleId: moduleId,
      resourceId: _opaqueResourceId(uri),
    );
  }

  return null;
}

String _normalizePath(String rawPath) {
  if (rawPath.isEmpty || rawPath == '/') return ShellDestination.home.path;
  final normalized = rawPath.startsWith('/') ? rawPath : '/$rawPath';
  return normalized.length > 1 && normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
}

String? _opaqueResourceId(Uri uri) {
  final value = uri.queryParameters['resourceId']?.trim();
  if (value == null || value.isEmpty) return null;
  return _isSafeStableId(value) ? value : null;
}

bool _isSafeStableId(String value) {
  if (value.isEmpty || value.length > 128) return false;
  return RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);
}

extension ShellDestinationPresentation on ShellDestination {
  IconData get icon => switch (this) {
    ShellDestination.home => Icons.home_outlined,
    ShellDestination.today => Icons.today_outlined,
    ShellDestination.journey => Icons.route_outlined,
    ShellDestination.circle => Icons.people_outline,
    ShellDestination.you => Icons.person_outline,
  };

  IconData get selectedIcon => switch (this) {
    ShellDestination.home => Icons.home_rounded,
    ShellDestination.today => Icons.today_rounded,
    ShellDestination.journey => Icons.route_rounded,
    ShellDestination.circle => Icons.people_rounded,
    ShellDestination.you => Icons.person_rounded,
  };
}
