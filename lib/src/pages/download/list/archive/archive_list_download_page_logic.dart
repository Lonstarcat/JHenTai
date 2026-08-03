import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/extension/get_logic_extension.dart';
import 'package:jhentai/src/mixin/update_global_gallery_status_logic_mixin.dart';
import 'package:jhentai/src/utils/toast_util.dart';
import '../../../../database/database.dart';
import '../../../../database/dao/archive_group_dao.dart';
import '../../../../mixin/scroll_to_top_logic_mixin.dart';
import '../../../../mixin/scroll_to_top_state_mixin.dart';
import '../../../../service/archive_download_service.dart';
import '../../../../service/local_config_service.dart';
import '../../../../setting/performance_setting.dart';
import '../../mixin/archive/archive_download_page_logic_mixin.dart';
import '../../mixin/archive/archive_download_page_state_mixin.dart';
import '../../mixin/basic/multi_select/multi_select_download_page_logic_mixin.dart';
import 'archive_list_download_page_state.dart';

class ArchiveListDownloadPageLogic extends GetxController
    with Scroll2TopLogicMixin, MultiSelectDownloadPageLogicMixin<ArchiveDownloadedData>, ArchiveDownloadPageLogicMixin, UpdateGlobalGalleryStatusLogicMixin {
  final String galleryId = 'galleryId';

  ArchiveListDownloadPageState state = ArchiveListDownloadPageState();

  @override
  Scroll2TopStateMixin get scroll2TopState => state;

  @override
  ArchiveDownloadPageStateMixin get archiveDownloadPageState => state;

  late Worker maxGalleryNum4AnimationListener;

  @override
  Future<void> onInit() async {
    super.onInit();

    String? displayGroupsString = await localConfigService.read(configKey: ConfigEnum.displayArchiveGroups);
    if (displayGroupsString == null) {
      state.displayGroups = {'default'.tr};
    } else {
      state.displayGroups = Set.from(jsonDecode(displayGroupsString));
    }
    state.displayGroupsCompleter.complete();

    maxGalleryNum4AnimationListener = ever(performanceSetting.maxGalleryNum4Animation, (_) => updateSafely([bodyId]));
  }

  @override
  void onClose() {
    super.onClose();

    maxGalleryNum4AnimationListener.dispose();
  }

  List<ArchiveDownloadedData> get sortedArchives {
    List<ArchiveDownloadedData> sorted = [...archiveDownloadService.archives];

    Map<String, int> groupOrder = {};
    for (int i = 0; i < archiveDownloadService.allGroups.length; i++) {
      groupOrder[archiveDownloadService.allGroups[i]] = i;
    }

    sorted.sort((a, b) {
      String aGroup = archiveDownloadService.archiveDownloadInfos[a.gid]!.group;
      String bGroup = archiveDownloadService.archiveDownloadInfos[b.gid]!.group;

      int groupCmp = (groupOrder[aGroup] ?? 9999).compareTo(groupOrder[bGroup] ?? 9999);
      if (groupCmp != 0) return groupCmp;

      switch (state.sortBy) {
        case SortBy.title:
          return a.title.compareTo(b.title);
        case SortBy.publishTime:
          return b.publishTime.compareTo(a.publishTime);
        case SortBy.insertTime:
          return b.insertTime.compareTo(a.insertTime);
      }
    });

    return sorted;
  }

  void toggleEditMode() {
    if (!state.inEditMode) {
      exitSelectMode();
      state.currentGroup = null;
      toast('sortGroupsHint'.tr);
    } else {
      state.currentGroup = null;
    }
    state.inEditMode = !state.inEditMode;
    updateSafely([bodyId]);
  }

  void enterGroup(String group) {
    state.currentGroup = group;
    updateSafely([bodyId]);
  }

  void backGroup() {
    state.currentGroup = null;
    updateSafely([bodyId]);
  }

  Future<void> saveArchiveOrderAfterReordered(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    List<ArchiveDownloadedData> archives;
    if (state.currentGroup != null) {
      archives = List.from(archiveDownloadService.archivesWithGroup(state.currentGroup!));
    } else {
      archives = List.from(archiveDownloadService.archives);
    }

    ArchiveDownloadedData moved = archives.removeAt(oldIndex);
    archives.insert(newIndex, moved);

    for (int i = 0; i < archives.length; i++) {
      archiveDownloadService.archiveDownloadInfos[archives[i].gid]!.sortOrder = i;
    }

    await archiveDownloadService.batchUpdateArchiveInDatabase(archives);
    updateSafely([bodyId]);
  }

  Future<void> saveGroupOrderAfterReordered(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    archiveDownloadService.allGroups.insert(newIndex, archiveDownloadService.allGroups.removeAt(oldIndex));

    for (int i = 0; i < archiveDownloadService.allGroups.length; i++) {
      await ArchiveGroupDao.updateArchiveGroupOrder(archiveDownloadService.allGroups[i], i);
    }
    updateSafely([bodyId]);
  }

  Future<void> toggleDisplayGroups(String groupName) async {
    await state.displayGroupsCompleter.future;

    if (state.displayGroups.contains(groupName)) {
      state.displayGroups.remove(groupName);
    } else {
      state.displayGroups.add(groupName);
    }

    await localConfigService.write(configKey: ConfigEnum.displayArchiveGroups, value: jsonEncode(state.displayGroups.toList()));

    state.groupedListController.toggleGroup(groupName);
  }

  @override
  Future<void> doRenameGroup(String oldGroup, String newGroup) async {
    await state.displayGroupsCompleter.future;

    state.displayGroups.remove(oldGroup);
    return super.doRenameGroup(oldGroup, newGroup);
  }

  @override
  Future<void> handleRemoveItem(ArchiveDownloadedData archive) async {
    bool confirmed = await confirmDestructiveAction(title: 'delete'.tr + '?');
    if (!confirmed) {
      return;
    }
    state.groupedListController.removeElement(archive).then((_) async {
      state.selectedGids.remove(archive.gid);
      await archiveDownloadService.deleteArchive(archive.gid);
      updateGlobalGalleryStatus();
    });
  }

  @override
  void handleResumeAllTasks() {
    archiveDownloadService.resumeAllDownloadArchive();
  }

  @override
  Future<void> selectAllItem() async {
    await state.displayGroupsCompleter.future;

    List<ArchiveDownloadedData> archives = [];
    for (String group in state.displayGroups) {
      archives.addAll(archiveDownloadService.archivesWithGroup(group));
    }

    multiSelectDownloadPageState.selectedGids.addAll(archives.map((archive) => archive.gid));
    updateSafely(multiSelectDownloadPageState.selectedGids.map((gid) => '$itemCardId::$gid').toList());
  }

  @override
  Future<void> changeParseSource(int gid, ArchiveParseSource parseSource) async {
    await super.changeParseSource(gid, parseSource);
    updateSafely(['$galleryId::$gid']);
  }
}
