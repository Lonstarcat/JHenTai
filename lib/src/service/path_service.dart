import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../utils/app_data_directory_util.dart';
import 'jh_service.dart';

PathService pathService = PathService();

class PathService with JHLifeCircleBeanErrorCatch implements JHLifeCircleBean {
  /// visible for all
  late Directory tempDir;

  /// visible on ios&windows&macos
  Directory? appDocDir;

  /// visible on windows
  Directory? appSupportDir;

  /// visible on android
  Directory? externalStorageDir;

  Directory? systemDownloadDir;

  @override
  List<JHLifeCircleBean> get initDependencies => [];

  @override
  Future<void> doInitBean() async {
    await Future.wait([
      getTemporaryDirectory().then((value) => tempDir = value),
      getApplicationDocumentsDirectory()
          .then((value) => appDocDir = value)
          .catchError((error) => null),
      getApplicationSupportDirectory()
          .then((value) => appSupportDir = value)
          .catchError((error) => null),
      getExternalStorageDirectory()
          .then((value) => externalStorageDir = value)
          .catchError((error) => null),
      getDownloadsDirectory()
          .then((value) => systemDownloadDir = value)
          .catchError((error) => null),
    ]);
  }

  @override
  Future<void> doAfterBeanReady() async {}

  Directory getVisibleDir() {
    return selectAppDataDirectory(
      platform: Platform.operatingSystem,
      appDocumentsDirectory: appDocDir,
      appSupportDirectory: appSupportDir,
      externalStorageDirectory: externalStorageDir,
      downloadsDirectory: systemDownloadDir,
    );
  }
}
