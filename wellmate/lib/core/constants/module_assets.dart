/// Package asset prefix needed when WellMate is included as a Flutter package
/// inside the parent app. Standalone APKs continue using root asset paths.
const String? wellMateAssetPackage =
    bool.fromEnvironment('LIFEMATE_SHELL_MODULES') ? 'wellmate' : null;
