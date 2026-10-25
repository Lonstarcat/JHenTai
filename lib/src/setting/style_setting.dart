import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/config/ui_config.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/service/jh_service.dart';
import 'package:jhentai/src/service/log.dart';
import 'package:jhentai/src/service/local_config_service.dart';
import '../model/download_multi_select_toolbar.dart';
import '../model/download_page_actions.dart';
import '../utils/serial_config_writer.dart';

import '../model/jh_layout.dart';

StyleSetting styleSetting = StyleSetting();

class StyleSetting
    with JHLifeCircleBeanWithConfigStorage
    implements JHLifeCircleBean {
  StyleSetting({Future<int> Function(String)? configWriter})
      : _configWriter = configWriter;

  final Future<int> Function(String)? _configWriter;
  final SerialConfigWriter _configWrites = SerialConfigWriter();
  final Rx<DownloadToolbarConfig> galleryToolbar =
      DownloadToolbarConfig.defaults(DownloadToolbarKind.gallery).obs;
  final Rx<DownloadToolbarConfig> archiveToolbar =
      DownloadToolbarConfig.defaults(DownloadToolbarKind.archive).obs;
  final RxBool savingToolbar = false.obs;
  int _pendingToolbarSaves = 0;
  final Rx<DownloadPageActionsConfig> downloadPageActions = DownloadPageActionsConfig.defaults().obs;
  final RxBool savingDownloadPageActions = false.obs;
  int _pendingPageActionSaves = 0;

  Future<void> updateDownloadPageActions(
      DownloadPageActionsConfig Function(DownloadPageActionsConfig) edit) {
    _pendingPageActionSaves++;
    savingDownloadPageActions.value = true;
    return _configWrites.run(() async {
      final previous = downloadPageActions.value;
      try {
        downloadPageActions.value = edit(previous);
        if (await _writeCurrentConfig() <= 0) {
          throw StateError('Style config was not saved');
        }
      } catch (_) {
        downloadPageActions.value = previous;
        rethrow;
      } finally {
        _pendingPageActionSaves--;
        savingDownloadPageActions.value = _pendingPageActionSaves > 0;
      }
    });
  }

  Rx<DownloadToolbarConfig> toolbarConfig(DownloadToolbarKind kind) =>
      kind == DownloadToolbarKind.gallery ? galleryToolbar : archiveToolbar;

  Future<int> _writeCurrentConfig() =>
      _configWriter?.call(toConfigString()) ??
      localConfigService.write(configKey: configEnum, value: toConfigString());

  @override
  Future<int> saveBeanConfig() => _configWrites.run(_writeCurrentConfig);

  /// A transaction applies immediately when its turn starts. Editor controls are
  /// disabled during writes; queued edits still derive from the latest confirmed
  /// state. Failure rolls back before the next write (also other style writes).
  Future<void> updateToolbar(DownloadToolbarKind kind,
      DownloadToolbarConfig Function(DownloadToolbarConfig) edit) {
    _pendingToolbarSaves++;
    savingToolbar.value = true;
    return _configWrites.run(() async {
      final target = toolbarConfig(kind);
      final previous = target.value;
      try {
        target.value = edit(previous);
        if (await _writeCurrentConfig() <= 0) {
          throw StateError('Style config was not saved');
        }
      } catch (_) {
        target.value = previous;
        rethrow;
      } finally {
        _pendingToolbarSaves--;
        savingToolbar.value = _pendingToolbarSaves > 0;
      }
    });
  }

  Rx<ThemeMode> themeMode = ThemeMode.system.obs;
  Rx<Color> lightThemeColor = UIConfig.defaultLightThemeColor.obs;
  Rx<Color> darkThemeColor = UIConfig.defaultDarkThemeColor.obs;
  Rx<ListMode> listMode = ListMode.listWithTags.obs;
  RxnInt crossAxisCountInWaterFallFlow = RxnInt(null);
  RxnInt crossAxisCountInGridDownloadPageForGroup = RxnInt(null);
  RxnInt crossAxisCountInGridDownloadPageForGallery = RxnInt(null);
  RxnInt crossAxisCountInDetailPage = RxnInt(null);
  RxMap<String, ListMode> pageListMode = <String, ListMode>{}.obs;
  RxBool moveCover2RightSide = false.obs;
  RxBool showTagIcons = false.obs;
  RxBool showAdsBadge = true.obs;
  RxBool showAiBadge = true.obs;
  Rx<LayoutMode> layout =
      PlatformDispatcher.instance.views.first.physicalSize.width /
                  PlatformDispatcher.instance.views.first.devicePixelRatio <
              600
          ? LayoutMode.mobileV2.obs
          : GetPlatform.isDesktop
              ? LayoutMode.desktop.obs
              : LayoutMode.tabletV2.obs;

  bool get isInWaterFlowListMode =>
      listMode.value == ListMode.waterfallFlowBig ||
      listMode.value == ListMode.waterfallFlowSmall ||
      listMode.value == ListMode.waterfallFlowMedium;

  Brightness currentBrightness() => themeMode.value == ThemeMode.system
      ? PlatformDispatcher.instance.platformBrightness
      : themeMode.value == ThemeMode.light
          ? Brightness.light
          : Brightness.dark;

  /// If the current window width is too small, App will degrade to mobile mode. Use [actualLayout] to indicate actual layout.
  LayoutMode actualLayout =
      PlatformDispatcher.instance.views.first.physicalSize.width /
                  PlatformDispatcher.instance.views.first.devicePixelRatio <
              600
          ? LayoutMode.mobileV2
          : GetPlatform.isDesktop
              ? LayoutMode.desktop
              : LayoutMode.tabletV2;

  bool get isInMobileLayout =>
      actualLayout == LayoutMode.mobileV2 || actualLayout == LayoutMode.mobile;

  bool get isInTabletLayout =>
      actualLayout == LayoutMode.tabletV2 || actualLayout == LayoutMode.tablet;

  bool get isInV1Layout =>
      actualLayout == LayoutMode.mobile || actualLayout == LayoutMode.tablet;

  bool get isInV2Layout =>
      actualLayout == LayoutMode.mobileV2 ||
      actualLayout == LayoutMode.tabletV2;

  bool get isInDesktopLayout => actualLayout == LayoutMode.desktop;

  @override
  ConfigEnum get configEnum => ConfigEnum.styleSetting;

  @override
  void applyBeanConfig(String configString) {
    Map map = jsonDecode(configString);

    themeMode.value = ThemeMode.values[map['themeMode']];
    lightThemeColor.value =
        Color(map['lightThemeColor'] ?? lightThemeColor.value.toARGB32());
    darkThemeColor.value =
        Color(map['darkThemeColor'] ?? darkThemeColor.value.toARGB32());
    listMode.value = ListMode.values[map['listMode']];
    crossAxisCountInWaterFallFlow.value = map['crossAxisCountInWaterFallFlow'];
    crossAxisCountInGridDownloadPageForGroup.value =
        map['crossAxisCountInGridDownloadPageForGroup'];
    crossAxisCountInGridDownloadPageForGallery.value =
        map['crossAxisCountInGridDownloadPageForGallery'];
    crossAxisCountInDetailPage.value = map['crossAxisCountInDetailPage'];
    pageListMode.value = Map.from(map['pageListMode']?.map(
            (route, listModeIndex) =>
                MapEntry(route, ListMode.values[listModeIndex])) ??
        {});
    moveCover2RightSide.value =
        map['moveCover2RightSide'] ?? moveCover2RightSide.value;
    showTagIcons.value =
        map['showTagIcons'] is bool ? map['showTagIcons'] : false;
    showAdsBadge.value = map['showAdsBadge'] is bool ? map['showAdsBadge'] : true;
    showAiBadge.value = map['showAiBadge'] is bool ? map['showAiBadge'] : true;
    galleryToolbar.value = DownloadToolbarConfig.fromJson(
        map['galleryMultiSelectToolbar'], DownloadToolbarKind.gallery);
    archiveToolbar.value = DownloadToolbarConfig.fromJson(
        map['archiveMultiSelectToolbar'], DownloadToolbarKind.archive);
    downloadPageActions.value = DownloadPageActionsConfig.fromJson(map['downloadPageActions']);
    layout.value = LayoutMode.values[map['layout'] ?? layout.value.index];

    /// old layout has been removed in v5.0.0
    if (isInV1Layout) {
      layout = PlatformDispatcher.instance.views.first.physicalSize.width /
                  PlatformDispatcher.instance.views.first.devicePixelRatio <
              600
          ? LayoutMode.mobileV2.obs
          : GetPlatform.isDesktop
              ? LayoutMode.desktop.obs
              : LayoutMode.tabletV2.obs;
    }
    actualLayout = layout.value;
  }

  @override
  String toConfigString() {
    return jsonEncode({
      'themeMode': themeMode.value.index,
      'lightThemeColor': lightThemeColor.value.toARGB32(),
      'darkThemeColor': darkThemeColor.value.toARGB32(),
      'listMode': listMode.value.index,
      'crossAxisCountInWaterFallFlow': crossAxisCountInWaterFallFlow.value,
      'crossAxisCountInGridDownloadPageForGroup':
          crossAxisCountInGridDownloadPageForGroup.value,
      'crossAxisCountInGridDownloadPageForGallery':
          crossAxisCountInGridDownloadPageForGallery.value,
      'crossAxisCountInDetailPage': crossAxisCountInDetailPage.value,
      'pageListMode': pageListMode
          .map((route, listMode) => MapEntry(route, listMode.index)),
      'moveCover2RightSide': moveCover2RightSide.value,
      'showTagIcons': showTagIcons.value,
      'showAdsBadge': showAdsBadge.value,
      'showAiBadge': showAiBadge.value,
      'galleryMultiSelectToolbar': galleryToolbar.value.toJson(),
      'archiveMultiSelectToolbar': archiveToolbar.value.toJson(),
      'downloadPageActions': downloadPageActions.value.toJson(),
      'layout': layout.value.index,
    });
  }

  @override
  Future<void> doInitBean() async {}

  @override
  void doAfterBeanReady() {
    ever(themeMode, (_) {
      Get.changeThemeMode(themeMode.value);
    });
  }

  Future<void> saveThemeMode(ThemeMode themeMode) async {
    log.debug('saveThemeMode:${themeMode.name}');
    this.themeMode.value = themeMode;
    await saveBeanConfig();
  }

  Future<void> saveShowTagIcons(bool value) async {
    showTagIcons.value = value;
    await saveBeanConfig();
  }

  Future<void> saveShowAdsBadge(bool value) async {
    showAdsBadge.value = value;
    await saveBeanConfig();
  }

  Future<void> saveShowAiBadge(bool value) async {
    showAiBadge.value = value;
    await saveBeanConfig();
  }

  Future<void> saveLightThemeColor(Color color) async {
    log.debug('saveLightThemeColor:$color');
    this.lightThemeColor.value = color;
    await saveBeanConfig();
  }

  Future<void> saveDarkThemeColor(Color color) async {
    log.debug('saveDarkThemeColor:$color');
    this.darkThemeColor.value = color;
    await saveBeanConfig();
  }

  Future<void> saveListMode(ListMode listMode) async {
    log.debug('saveListMode:${listMode.name}');
    this.listMode.value = listMode;
    await saveBeanConfig();
  }

  Future<void> saveCrossAxisCountInWaterFallFlow(
      int? crossAxisCountInWaterFallFlow) async {
    log.debug(
        'saveCrossAxisCountInWaterFallFlow:$crossAxisCountInWaterFallFlow');
    this.crossAxisCountInWaterFallFlow.value = crossAxisCountInWaterFallFlow;
    await saveBeanConfig();
  }

  Future<void> saveCrossAxisCountInGridDownloadPageForGroup(
      int? crossAxisCountInGridDownloadPageForGroup) async {
    log.debug(
        'saveCrossAxisCountInGridDownloadPageForGroup:$crossAxisCountInGridDownloadPageForGroup');
    this.crossAxisCountInGridDownloadPageForGroup.value =
        crossAxisCountInGridDownloadPageForGroup;
    await saveBeanConfig();
  }

  Future<void> saveCrossAxisCountInGridDownloadPageForGallery(
      int? crossAxisCountInGridDownloadPageForGallery) async {
    log.debug(
        'saveCrossAxisCountInGridDownloadPageForGallery:$crossAxisCountInGridDownloadPageForGallery');
    this.crossAxisCountInGridDownloadPageForGallery.value =
        crossAxisCountInGridDownloadPageForGallery;
    await saveBeanConfig();
  }

  Future<void> saveCrossAxisCountInDetailPage(
      int? crossAxisCountInDetailPage) async {
    log.debug('saveCrossAxisCountInDetailPage:$crossAxisCountInDetailPage');
    this.crossAxisCountInDetailPage.value = crossAxisCountInDetailPage;
    await saveBeanConfig();
  }

  Future<void> savePageListMode(String routeName, ListMode? listMode) async {
    log.debug('savePageListMode:$routeName, $listMode');
    if (listMode == null) {
      this.pageListMode.remove(routeName);
    } else {
      this.pageListMode[routeName] = listMode;
    }
    await saveBeanConfig();
  }

  Future<void> saveMoveCover2RightSide(bool moveCover2RightSide) async {
    log.debug('saveMoveCover2RightSide:$moveCover2RightSide');
    this.moveCover2RightSide.value = moveCover2RightSide;
    await saveBeanConfig();
  }

  Future<void> saveLayoutMode(LayoutMode layoutMode) async {
    log.debug('saveLayoutMode:${layoutMode.name}');
    this.layout.value = layoutMode;
    await saveBeanConfig();
  }
}

enum ListMode {
  listWithoutTags,
  listWithTags,
  waterfallFlowSmall,
  waterfallFlowBig,
  flat,
  flatWithoutTags,
  waterfallFlowMedium,
}
