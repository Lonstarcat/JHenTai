import 'dart:io';

/// Selects an app-specific storage root without reading or migrating old data.
/// Never fall back to shared Documents on desktop: this would let two installed
/// identities silently share a database/config and write to the same library.
Directory selectAppDataDirectory({
  required String platform,
  Directory? appDocumentsDirectory,
  Directory? appSupportDirectory,
  Directory? externalStorageDirectory,
  Directory? downloadsDirectory,
}) {
  if (platform == 'android' && externalStorageDirectory != null) {
    return externalStorageDirectory;
  }
  if (platform == 'macos' || platform == 'windows' || platform == 'linux') {
    return appSupportDirectory ??
        (throw StateError(
            'Application support directory unavailable on $platform'));
  }
  return appDocumentsDirectory ??
      appSupportDirectory ??
      downloadsDirectory ??
      (throw StateError('Application data directory unavailable on $platform'));
}
