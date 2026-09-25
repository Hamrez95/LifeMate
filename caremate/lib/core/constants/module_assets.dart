/// Package asset prefix needed when CareMate is included as a Flutter package
/// inside the parent app. Standalone APKs continue using root asset paths.
const String? careMateAssetPackage =
    bool.fromEnvironment('LIFEMATE_SHELL_MODULES') ? 'caremate' : null;
