library lifemate_core;

// Keep the package's canonical/native API as the default export so analyzer,
// VM tests and native builds retain the complete offline runtime surface.
// Browser compilation is the exceptional target and receives only the
// deliberately narrow, PHI-store-free contracts.
export 'lifemate_core_native.dart'
    if (dart.library.html) 'lifemate_core_web.dart';
