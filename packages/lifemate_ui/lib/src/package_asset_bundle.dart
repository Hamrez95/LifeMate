import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Resolves unqualified asset names from a Flutter package before the host app.
///
/// Embedded product modules often use the same asset paths as their standalone
/// hosts. Flutter stores package assets under `packages/<package>/...`; this
/// bundle lets existing module widgets resolve those assets without changing
/// standalone asset names or duplicating files in the parent app.
class LifeMatePackageAssetBundle extends StatelessWidget {
  const LifeMatePackageAssetBundle({
    super.key,
    required this.packageName,
    required this.child,
  });

  final String packageName;
  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultAssetBundle(
        bundle: _PackageAssetBundle(packageName),
        child: child,
      );
}

class _PackageAssetBundle extends CachingAssetBundle {
  _PackageAssetBundle(this.packageName);

  final String packageName;

  @override
  Future<ByteData> load(String key) async {
    if (key.startsWith('packages/')) return rootBundle.load(key);
    try {
      return await rootBundle.load('packages/$packageName/$key');
    } on FlutterError {
      return rootBundle.load(key);
    }
  }
}
