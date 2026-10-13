import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/utils/app_data_directory_util.dart';

void main() {
  final documents = Directory('shared-documents');
  final support = Directory('isolated-support');
  final external = Directory('android-package-files');
  final downloads = Directory('shared-downloads');

  for (final platform in ['macos', 'windows', 'linux']) {
    test('$platform selects isolated support instead of shared documents', () {
      expect(
          selectAppDataDirectory(
            platform: platform,
            appDocumentsDirectory: documents,
            appSupportDirectory: support,
            downloadsDirectory: downloads,
          ),
          same(support));
    });
    test('$platform fails instead of silently sharing old data', () {
      expect(
          () => selectAppDataDirectory(
                platform: platform,
                appDocumentsDirectory: documents,
                downloadsDirectory: downloads,
              ),
          throwsStateError);
    });
  }
  test('Android retains package-specific external storage', () {
    expect(
        selectAppDataDirectory(
          platform: 'android',
          appDocumentsDirectory: documents,
          appSupportDirectory: support,
          externalStorageDirectory: external,
        ),
        same(external));
  });
  test('iOS retains its app container Documents', () {
    expect(
        selectAppDataDirectory(
          platform: 'ios',
          appDocumentsDirectory: documents,
          appSupportDirectory: support,
        ),
        same(documents));
  });
}
