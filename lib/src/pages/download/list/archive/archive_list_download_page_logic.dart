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
import '../../download_reorder_mode.dart';
import '../widget/download_reorder_widgets.dart';
import 'archive_list_download_page_state.dart';

class ArchiveListDownloadPageLogic extends GetxController
    with
        Scroll2TopLogicMixin,
        MultiSelectDownloadPageLogicMixin<ArchiveDownloadedData>,
        ArchiveDownloadPageLogicMixin,
        UpdateGlobalGalleryStatusLogicMixin
    implements DownloadReorderModeParticipant {
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

    String? displayGroupsString = await localConfigService.read(
        configKey: ConfigEnum.displayArchiveGroups);
    if (displayGroupsString == null) {
      state.displayGroups = {'default'.tr};
    } else {
      state.displayGroups = Set.from(jsonDecode(displayGroupsString));
    }
    state.displayGroupsCompleter.complete();

    maxGalleryNum4AnimationListener = ever(
        performanceSetting.maxGalleryNum4Animation,
        (_) => updateSafely([bodyId]));
  }

  @override
  void onClose() {
    unregisterDownloadReorderMode(this);
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

      int groupCmp =
          (groupOrder[aGroup] ?? 9999).compareTo(groupOrder[bGroup] ?? 9999);
      if (groupCmp != 0) {
        return groupCmp;
      }

      switch (state.sortBy) {
        case SortBy.manual:
          return compareDownloadManualOrder(
            firstOrder:
                archiveDownloadService.archiveDownloadInfos[a.gid]!.sortOrder,
            secondOrder:
                archiveDownloadService.archiveDownloadInfos[b.gid]!.sortOrder,
            fallbackComparison: b.insertTime.compareTo(a.insertTime),
          );
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

  List<DownloadReorderEntry<ArchiveDownloadedData>> get reorderEntries {
    final List<ArchiveDownloadedData> displayedArchives = sortedArchives;
    return buildDownloadReorderEntries(
      groups: archiveDownloadService.allGroups,
      isGroupOpen: state.displayGroups.contains,
      itemsForGroup: (group) => displayedArchives.where((archive) =>
          archiveDownloadService.archiveDownloadInfos[archive.gid]!.group ==
          group),
    );
  }

  void toggleEditMode() {
    if (state.inEditMode) {
      exitEditMode();
      return;
    }
    final double? scrollOffset = state.scrollController.hasClients
        ? state.scrollController.offset
        : null;
    exitSelectMode();
    toast('sortGroupsHint'.tr);
    state.inEditMode = true;
    registerDownloadReorderMode(this);
    updateSafely([bodyId]);
    restoreDownloadListScrollOffset(state.scrollController, scrollOffset);
  }

  @override
  void exitEditMode() {
    if (!state.inEditMode) {
      return;
    }
    final double? scrollOffset = state.scrollController.hasClients
        ? state.scrollController.offset
        : null;
    state.inEditMode = false;
    unregisterDownloadReorderMode(this);
    updateSafely([bodyId]);
    restoreDownloadListScrollOffset(state.scrollController, scrollOffset);
  }

  Future<void> saveOrderAfterReordered(
    List<DownloadReorderEntry<ArchiveDownloadedData>> entries,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) {
      return;
    }

    final DownloadReorderEntry<ArchiveDownloadedData> moved = entries[oldIndex];
    final List<DownloadReorderEntry<ArchiveDownloadedData>> reordered =
        reorderDownloadEntries(entries, oldIndex, newIndex);

    if (moved.isGroup) {
      final List<String> groups = reordered
          .where((entry) => entry.isGroup)
          .map((entry) => entry.groupName)
          .toList();
      archiveDownloadService.allGroups
        ..clear()
        ..addAll(groups);
      updateSafely([bodyId]);
      for (int i = 0; i < groups.length; i++) {
        await ArchiveGroupDao.updateArchiveGroupOrder(groups[i], i);
      }
    } else {
      final List<ArchiveDownloadedData> archives = reordered
          .where(
              (entry) => !entry.isGroup && entry.groupName == moved.groupName)
          .map((entry) => entry.item!)
          .toList();
      for (int i = 0; i < archives.length; i++) {
        archiveDownloadService
            .archiveDownloadInfos[archives[i].gid]!.sortOrder = i;
      }
      state.sortBy = SortBy.manual;
      updateSafely([bodyId]);
      await archiveDownloadService.batchUpdateArchiveInDatabase(archives);
    }
  }

  Future<void> toggleDisplayGroups(String groupName) async {
    await state.displayGroupsCompleter.future;

    if (state.displayGroups.contains(groupName)) {
      state.displayGroups.remove(groupName);
    } else {
      state.displayGroups.add(groupName);
    }

    await localConfigService.write(
        configKey: ConfigEnum.displayArchiveGroups,
        value: jsonEncode(state.displayGroups.toList()));

    if (state.inEditMode) {
      updateSafely([bodyId]);
    } else {
      state.groupedListController.toggleGroup(groupName);
    }
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

    multiSelectDownloadPageState.selectedGids
        .addAll(archives.map((archive) => archive.gid));
    updateSafely(multiSelectDownloadPageState.selectedGids
        .map((gid) => '$itemCardId::$gid')
        .toList());
  }

  @override
  Future<void> changeParseSource(
      int gid, ArchiveParseSource parseSource) async {
    await super.changeParseSource(gid, parseSource);
    updateSafely(['$galleryId::$gid']);
  }
}
