import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:jhentai/src/config/ui_config.dart';
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
import '../../../../utils/download_task_locator_util.dart';
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

  List<ArchiveDownloadedData> reorderArchivesInGroup(String group) {
    return sortedArchives
        .where((archive) =>
            archiveDownloadService.archiveDownloadInfos[archive.gid]!.group ==
            group)
        .toList();
  }

  @override
  Future<bool> locateDownloadTask(int gid, BuildContext context) async {
    await state.displayGroupsCompleter.future;
    ArchiveDownloadedData? target;
    for (final ArchiveDownloadedData archive
        in archiveDownloadService.archives) {
      if (archive.gid == gid) {
        target = archive;
        break;
      }
    }
    if (target == null) {
      return false;
    }

    exitEditMode();
    final String group =
        archiveDownloadService.archiveDownloadInfos[gid]!.group;
    if (!state.displayGroups.contains(group)) {
      await toggleDisplayGroups(group);
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }

    final List<ArchiveDownloadedData> groupItems =
        reorderArchivesInGroup(group);
    final int targetIndex = groupItems.indexWhere((item) => item.gid == gid);
    if (targetIndex < 0) {
      return false;
    }
    final double offset = downloadListTaskOffset(
      groups: archiveDownloadService.allGroups,
      expandedGroups: state.displayGroups,
      targetGroup: group,
      targetIndex: targetIndex,
      itemCount: (name) => reorderArchivesInGroup(name).length,
      groupExtent: UIConfig.groupListHeight + 10,
      itemExtent: UIConfig.downloadPageCardHeight + 10,
    );
    final GlobalKey itemKey = state.navigationItemKeys
        .putIfAbsent(gid, () => GlobalKey(debugLabel: 'archive-$gid'));
    updateSafely([bodyId]);
    try {
      return await revealDownloadTask(
        controller: state.scrollController,
        itemKey: itemKey,
        estimatedOffset: offset,
      );
    } finally {
      state.navigationItemKeys.remove(gid);
      updateSafely([bodyId]);
    }
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
    state.reorderExpansionSession.start(state.displayGroups);
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
    state.reorderExpansionSession.restore(state.displayGroups);
    state.inEditMode = false;
    unregisterDownloadReorderMode(this);
    updateSafely([bodyId]);
    restoreDownloadListScrollOffset(state.scrollController, scrollOffset);
  }

  void handleGroupReorderStart() {
    if (state.displayGroups.isEmpty) {
      return;
    }
    state.reorderExpansionSession.collapseAll(state.displayGroups);
    updateSafely([bodyId]);
  }

  Future<void> saveGroupOrderAfterReordered(
    List<String> groups,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) {
      return;
    }

    final List<String> reordered =
        reorderDownloadList(groups, oldIndex, newIndex);
    archiveDownloadService.allGroups
      ..clear()
      ..addAll(reordered);
    updateSafely([bodyId]);
    for (int i = 0; i < reordered.length; i++) {
      await ArchiveGroupDao.updateArchiveGroupOrder(reordered[i], i);
    }
  }

  Future<void> saveArchiveOrderAfterReordered(
    String group,
    List<ArchiveDownloadedData> archives,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex ||
        archives.any((archive) =>
            archiveDownloadService.archiveDownloadInfos[archive.gid]!.group !=
            group)) {
      return;
    }

    final List<ArchiveDownloadedData> reordered =
        reorderDownloadList(archives, oldIndex, newIndex);
    for (int i = 0; i < reordered.length; i++) {
      archiveDownloadService.archiveDownloadInfos[reordered[i].gid]!.sortOrder =
          i;
    }
    state.sortBy = SortBy.manual;
    updateSafely([bodyId]);
    await archiveDownloadService.batchUpdateArchiveInDatabase(reordered);
  }

  Future<void> toggleDisplayGroups(String groupName) async {
    await state.displayGroupsCompleter.future;

    if (state.displayGroups.contains(groupName)) {
      state.displayGroups.remove(groupName);
    } else {
      state.displayGroups.add(groupName);
    }

    if (state.inEditMode) {
      updateSafely([bodyId]);
    } else {
      await localConfigService.write(
          configKey: ConfigEnum.displayArchiveGroups,
          value: jsonEncode(state.displayGroups.toList()));
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
