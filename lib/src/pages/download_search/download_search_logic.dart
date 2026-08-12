import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/extension/get_logic_extension.dart';
import 'package:jhentai/src/service/local_config_service.dart';
import 'package:jhentai/src/service/log.dart';
import 'package:jhentai/src/service/tag_translation_service.dart';
import 'package:jhentai/src/utils/convert_util.dart';
import 'package:jhentai/src/utils/string_uril.dart';
import 'package:jhentai/src/widget/loading_state_indicator.dart';

import '../../config/ui_config.dart';
import '../../database/database.dart';
import '../../mixin/update_global_gallery_status_logic_mixin.dart';
import '../../model/gallery_image.dart';
import '../../model/read_page_info.dart';
import '../../routes/routes.dart';
import '../../service/archive_download_service.dart';
import '../../service/gallery_download/download_path_resolver.dart';
import '../../service/gallery_download/gallery_download_service.dart';
import '../../service/super_resolution_service.dart';
import '../../setting/preference_setting.dart';
import '../../setting/read_setting.dart';
import '../../utils/date_util.dart';
import '../../utils/process_util.dart';
import '../../utils/route_util.dart';
import '../../utils/table.dart' as t;
import '../../widget/eh_alert_dialog.dart';
import '../../widget/eh_context_menu.dart';
import '../../widget/eh_download_dialog.dart';
import 'download_search_query.dart';
import 'download_search_scheduler.dart';
import 'download_search_state.dart';

class DownloadSearchLogic extends GetxController
    with UpdateGlobalGalleryStatusLogicMixin {
  final DownloadSearchState state = DownloadSearchState();

  final String loadingStateId = 'loadingStateId';
  final String searchFieldId = 'searchFieldId';
  final String bodyId = 'bodyId';

  late final TextEditingController textEditingController;
  late final FocusNode searchFocusNode;
  late final ScrollController scrollController;

  final DownloadSearchScheduler _searchScheduler = DownloadSearchScheduler();

  LoadingState loadingState = LoadingState.idle;

  @override
  Future<void> onInit() async {
    super.onInit();

    textEditingController = TextEditingController();
    searchFocusNode = FocusNode();
    scrollController = ScrollController();

    try {
      String? code = await localConfigService.read(
          configKey: ConfigEnum.downloadSearchPageType);
      if (code != null) {
        state.searchType = DownloadSearchConfigTypeEnum.fromCode(
            int.tryParse(code) ?? DownloadSearchConfigTypeEnum.simple.code);
      }
    } catch (error, stackTrace) {
      log.error('Failed to initialize download search type', error, stackTrace);
    } finally {
      if (!state.searchTypeCompleter.isCompleted) {
        state.searchTypeCompleter.complete();
      }
    }
  }

  @override
  void onClose() {
    textEditingController.dispose();
    searchFocusNode.dispose();
    _searchScheduler.dispose();
    scrollController.dispose();
    super.onClose();
  }

  void handleTapClearButton() {
    textEditingController.clear();
    handleSearchFieldChanged('');
  }

  void handleSearchFieldChanged(String value) {
    if (value.isBlank!) {
      _clearSearch();
      return;
    }

    _searchScheduler.schedule((requestId) => _search(value, requestId));
  }

  void _clearSearch() {
    _searchScheduler.cancel();
    state.galleries.clear();
    state.archives.clear();
    state.searchErrorKey = null;
    loadingState = LoadingState.idle;
    updateSafely([searchFieldId, loadingStateId, bodyId]);
  }

  Future<void> _search(String value, int requestId) async {
    if (!_searchScheduler.isCurrent(requestId)) {
      return;
    }

    log.info('search downloaded info: $value');

    loadingState = LoadingState.loading;
    state.galleries.clear();
    state.archives.clear();
    updateSafely([loadingStateId, bodyId]);

    bool completedSuccessfully = false;
    try {
      await state.searchTypeCompleter.future;
      if (!_searchScheduler.isCurrent(requestId)) {
        return;
      }

      DownloadSearchConfigTypeEnum searchType = state.searchType;
      bool caseSensitive = state.caseSensitive;
      RegExp? regExp;
      if (searchType == DownloadSearchConfigTypeEnum.regex) {
        try {
          regExp = buildDownloadSearchRegExp(
              query: value, caseSensitive: caseSensitive);
        } on FormatException {
          state.searchErrorKey = 'invalidRegex';
          loadingState = LoadingState.success;
          return;
        }
      }

      state.searchErrorKey = null;

      List<TagData> allGalleryTags = galleryDownloadService.galleries
          .map((g) => g.tags)
          .mapMany(tagDataString2TagDataList)
          .toList();
      List<TagData> allArchiveTags = archiveDownloadService.archives
          .map((a) => a.tags)
          .mapMany(tagDataString2TagDataList)
          .toList();
      List<TagData> allTags = {...allGalleryTags, ...allArchiveTags}.toList();
      List<TagData> translatedTags =
          await tagTranslationService.translateTagDatasIfNeeded(allTags);
      if (!_searchScheduler.isCurrent(requestId)) {
        return;
      }

      t.Table<String, String, TagData> translatedTagDataTable = t.Table();
      for (TagData tag in translatedTags) {
        translatedTagDataTable.put(tag.namespace, tag.key, tag);
      }

      List<GallerySearchVO> gallerys = galleryDownloadService.galleries
          .map(
            (g) => GallerySearchVO(
              gid: g.gid,
              token: g.token,
              title: g.title,
              category: g.category,
              pageCount: g.pageCount,
              galleryUrl: g.galleryUrl,
              oldVersionGalleryUrl: g.oldVersionGalleryUrl,
              uploader: g.uploader,
              publishTime: preferenceSetting.showUtcTime.isTrue
                  ? g.publishTime
                  : DateUtil.transformUtc2LocalTimeString(g.publishTime),
              insertTime: g.insertTime,
              downloadOriginalImage: g.downloadOriginalImage,
              priority: g.priority,
              sortOrder: g.sortOrder,
              groupName: g.group,
              tags: tagDataString2TagDataList(g.tags)
                  .map((tagData) =>
                      translatedTagDataTable.get(
                          tagData.namespace, tagData.key) ??
                      tagData)
                  .toList(),
              tagRefreshTime: g.tagRefreshTime,
            ),
          )
          .toList();
      List<ArchiveSearchVO> archives = archiveDownloadService.archives.map((a) {
        return ArchiveSearchVO(
          gid: a.gid,
          token: a.token,
          title: a.title,
          category: a.category,
          pageCount: a.pageCount,
          galleryUrl: a.galleryUrl,
          coverUrl: a.coverUrl,
          uploader: a.uploader,
          size: a.size,
          publishTime: preferenceSetting.showUtcTime.isTrue
              ? a.publishTime
              : DateUtil.transformUtc2LocalTimeString(a.publishTime),
          archivePageUrl: a.archivePageUrl,
          downloadPageUrl: a.downloadPageUrl,
          downloadUrl: a.downloadUrl,
          isOriginal: a.isOriginal,
          insertTime: a.insertTime,
          sortOrder: a.sortOrder,
          groupName: a.groupName,
          tags: tagDataString2TagDataList(a.tags)
              .map((tagData) =>
                  translatedTagDataTable.get(tagData.namespace, tagData.key) ??
                  tagData)
              .toList(),
          tagRefreshTime: a.tagRefreshTime,
        );
      }).toList();

      List<GallerySearchVO> matchedGallerys = gallerys.where((gallery) {
        List<String> fields = _buildSearchableFields(
            gallery.title, gallery.uploader, gallery.tags);
        return regExp != null
            ? regExp.hasMatch(fields.join('\n'))
            : matchesDownloadSimpleQuery(
                fields: fields, query: value, caseSensitive: caseSensitive);
      }).toList();
      List<ArchiveSearchVO> matchedArchives = archives.where((archive) {
        List<String> fields = _buildSearchableFields(
            archive.title, archive.uploader, archive.tags);
        return regExp != null
            ? regExp.hasMatch(fields.join('\n'))
            : matchesDownloadSimpleQuery(
                fields: fields, query: value, caseSensitive: caseSensitive);
      }).toList();

      if (!_searchScheduler.isCurrent(requestId)) {
        return;
      }

      state.galleries = matchedGallerys;
      state.archives = matchedArchives;
      completedSuccessfully = true;
    } catch (error, stackTrace) {
      log.error('Failed to search downloaded info: $value', error, stackTrace);
      if (_searchScheduler.isCurrent(requestId)) {
        loadingState = LoadingState.error;
      }
    } finally {
      if (_searchScheduler.isCurrent(requestId)) {
        if (completedSuccessfully) {
          loadingState = LoadingState.success;
        } else if (loadingState == LoadingState.loading) {
          loadingState = LoadingState.error;
        }
        updateSafely([searchFieldId, loadingStateId, bodyId]);
      }
    }
  }

  Future<void> toggleSearchType() async {
    await state.searchTypeCompleter.future;

    state.searchType = state.searchType == DownloadSearchConfigTypeEnum.simple
        ? DownloadSearchConfigTypeEnum.regex
        : DownloadSearchConfigTypeEnum.simple;
    if (state.searchType == DownloadSearchConfigTypeEnum.simple) {
      state.searchErrorKey = null;
    }
    updateSafely([searchFieldId]);
    handleSearchFieldChanged(textEditingController.text);
    await localConfigService.write(
        configKey: ConfigEnum.downloadSearchPageType,
        value: state.searchType.code.toString());
  }

  void toggleCaseSensitive() {
    state.caseSensitive = !state.caseSensitive;
    updateSafely([searchFieldId]);
    handleSearchFieldChanged(textEditingController.text);
  }

  List<String> _buildSearchableFields(
      String title, String? uploader, List<TagData> tags) {
    return [
      title,
      if (!isEmptyOrNull(uploader)) uploader!,
      for (TagData tagData in tags) ...[
        '${tagData.namespace}:${tagData.key}',
        if (tagData.translatedNamespace != null && tagData.tagName != null)
          '${tagData.translatedNamespace}:${tagData.tagName}',
      ],
    ];
  }

  Future<void> goToGalleryReadPage(GallerySearchVO gallery) async {
    if (!galleryDownloadService.containGallery(gallery.gid)) {
      return;
    }

    if (readSetting.useThirdPartyViewer.isTrue &&
        readSetting.thirdPartyViewerPath.value != null) {
      GalleryDownloadInfo galleryData =
          galleryDownloadService.galleryDownloadInfos[gallery.gid]!;
      openThirdPartyViewer(
          DownloadPathResolver.computeGalleryDownloadAbsolutePath(
              galleryData.toGalleryDownloadedData()));
    } else {
      String? string = await localConfigService.read(
          configKey: ConfigEnum.readIndexRecord,
          subConfigKey: gallery.gid.toString());
      int readIndexRecord = (string == null ? 0 : (int.tryParse(string) ?? 0));

      /// Ensure the lazily-managed image list is resident before reading.
      await galleryDownloadService.galleryDownloadInfos[gallery.gid]!
          .ensureImagesLoaded();

      toRoute(
        Routes.read,
        arguments: ReadPageInfo(
          mode: ReadMode.downloaded,
          gid: gallery.gid,
          token: gallery.token,
          galleryTitle: gallery.title,
          galleryUrl: gallery.galleryUrl,
          initialIndex: readIndexRecord,
          readProgressRecordStorageKey: gallery.gid.toString(),
          pageCount: gallery.pageCount,
          useSuperResolution: superResolutionService.get(
                  gallery.gid, SuperResolutionType.gallery) !=
              null,
        ),
      );
    }
  }

  Future<void> goToArchiveReadPage(ArchiveSearchVO archive) async {
    if (archiveDownloadService
            .archiveDownloadInfos[archive.gid]?.archiveStatus !=
        ArchiveStatus.completed) {
      return;
    }

    if (readSetting.useThirdPartyViewer.isTrue &&
        readSetting.thirdPartyViewerPath.value != null) {
      ArchiveDownloadedData archiveData = archiveDownloadService.archives
          .firstWhere((a) => a.gid == archive.gid);
      openThirdPartyViewer(
          archiveDownloadService.computeArchiveUnpackingPath(archiveData));
    } else {
      String? string = await localConfigService.read(
          configKey: ConfigEnum.readIndexRecord,
          subConfigKey: archive.gid.toString());
      int readIndexRecord = (string == null ? 0 : (int.tryParse(string) ?? 0));

      List<GalleryImage> images =
          await archiveDownloadService.getUnpackedImages(archive.gid);

      toRoute(
        Routes.read,
        arguments: ReadPageInfo(
          mode: ReadMode.archive,
          gid: archive.gid,
          galleryTitle: archive.title,
          galleryUrl: archive.galleryUrl,
          initialIndex: readIndexRecord,
          pageCount: images.length,
          isOriginal: archive.isOriginal,
          readProgressRecordStorageKey: archive.gid.toString(),
          images: images,
          useSuperResolution: superResolutionService.get(
                  archive.gid, SuperResolutionType.archive) !=
              null,
        ),
      );
    }
  }

  void onLongPressGallery(BuildContext context, GallerySearchVO gallery,
      {Offset? position}) {
    showEHContextMenu(
      context,
      position: position,
      actions: [
        EHContextMenuAction(
          text: 'changeGroup'.tr,
          onTap: () => handleChangeGalleryGroup(gallery),
        ),
        EHContextMenuAction(
          text: 'deleteTaskAndImages'.tr,
          color: UIConfig.alertColor(context),
          onTap: () => handleRemoveGallery(gallery, context),
        ),
      ],
    );
  }

  void onLongPressArchive(BuildContext context, ArchiveSearchVO archive,
      {Offset? position}) {
    showEHContextMenu(
      context,
      position: position,
      actions: [
        EHContextMenuAction(
          text: 'changeGroup'.tr,
          onTap: () => handleChangeArchiveGroup(archive),
        ),
        EHContextMenuAction(
          text: 'delete'.tr,
          color: UIConfig.alertColor(context),
          onTap: () => handleRemoveArchive(archive),
        ),
      ],
    );
  }

  Future<void> handleChangeGalleryGroup(GallerySearchVO gallery) async {
    String oldGroup =
        galleryDownloadService.galleryDownloadInfos[gallery.gid]!.group;

    ({String group, bool downloadOriginalImage})? result = await Get.dialog(
      EHDownloadDialog(
        title: 'changeGroup'.tr,
        currentGroup: oldGroup,
        candidates: galleryDownloadService.allGroups,
      ),
    );

    if (result == null) {
      return;
    }

    String newGroup = result.group;
    if (newGroup == oldGroup) {
      return;
    }

    await galleryDownloadService.updateGroupByGid(gallery.gid, newGroup);

    update([bodyId]);
  }

  void handleRemoveGallery(
      GallerySearchVO gallery, BuildContext context) async {
    bool isUpdatingDependent =
        galleryDownloadService.isUpdatingDependent(gallery.gid);

    if (isUpdatingDependent) {
      bool? result = await showDialog(
        context: context,
        builder: (_) => EHDialog(
          title: 'delete'.tr + '?',
          content: 'deleteUpdatingDependentHint'.tr,
        ),
      );
      if (result == null || !result) {
        return;
      }
    } else if (preferenceSetting.confirmDestructiveActions.isTrue) {
      bool? result = await Get.dialog(EHDialog(title: 'delete'.tr + '?'));
      if (result == null || !result) {
        return;
      }
    }

    state.galleries.remove(gallery);
    await galleryDownloadService.deleteGalleryByGid(gallery.gid);
    update([bodyId]);
    updateGlobalGalleryStatus();
  }

  Future<void> handleChangeArchiveGroup(ArchiveSearchVO archive) async {
    String oldGroup =
        archiveDownloadService.archiveDownloadInfos[archive.gid]!.group;

    ({String group, bool downloadOriginalImage})? result = await Get.dialog(
      EHDownloadDialog(
        title: 'changeGroup'.tr,
        currentGroup: oldGroup,
        candidates: archiveDownloadService.allGroups,
      ),
    );

    if (result == null) {
      return;
    }

    String newGroup = result.group;
    if (newGroup == oldGroup) {
      return;
    }

    await archiveDownloadService.updateArchiveGroup(archive.gid, newGroup);
    update([bodyId]);
  }

  Future<void> handleRemoveArchive(ArchiveSearchVO archive) async {
    if (preferenceSetting.confirmDestructiveActions.isTrue) {
      bool? result = await Get.dialog(EHDialog(title: 'delete'.tr + '?'));
      if (result == null || !result) {
        return;
      }
    }
    state.archives.remove(archive);
    await archiveDownloadService.deleteArchive(archive.gid);
    update([bodyId]);
    updateGlobalGalleryStatus();
  }
}
