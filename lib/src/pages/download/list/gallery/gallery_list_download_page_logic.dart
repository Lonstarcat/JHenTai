import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/extension/get_logic_extension.dart';
import 'package:jhentai/src/pages/download/mixin/gallery/gallery_download_page_logic_mixin.dart';
import 'package:jhentai/src/setting/performance_setting.dart';
import 'package:jhentai/src/utils/toast_util.dart';

import '../../../../mixin/scroll_to_top_logic_mixin.dart';
import '../../../../mixin/scroll_to_top_state_mixin.dart';
import '../../../../mixin/update_global_gallery_status_logic_mixin.dart';
import '../../../../service/gallery_download/gallery_download_service.dart';
import '../../../../service/local_config_service.dart';
import '../../../../widget/eh_alert_dialog.dart';
import '../../mixin/basic/multi_select/multi_select_download_page_logic_mixin.dart';
import '../../mixin/basic/multi_select/multi_select_download_page_state_mixin.dart';
import '../../download_reorder_mode.dart';
import '../widget/download_reorder_widgets.dart';
import 'gallery_list_download_page_state.dart';

class GalleryListDownloadPageLogic extends GetxController
    with
        Scroll2TopLogicMixin,
        MultiSelectDownloadPageLogicMixin<GalleryDownloadInfo>,
        GalleryDownloadPageLogicMixin,
        UpdateGlobalGalleryStatusLogicMixin
    implements DownloadReorderModeParticipant {
  GalleryListDownloadPageState state = GalleryListDownloadPageState();

  @override
  MultiSelectDownloadPageStateMixin get multiSelectDownloadPageState => state;

  @override
  Scroll2TopStateMixin get scroll2TopState => state;

  late Worker maxGalleryNum4AnimationListener;

  @override
  Future<void> onInit() async {
    super.onInit();

    String? displayGroupsString = await localConfigService.read(
        configKey: ConfigEnum.displayGalleryGroups);
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

  List<GalleryDownloadInfo> get sortedGalleries {
    final List<GalleryDownloadInfo> sorted = [...downloadService.galleries];
    final Map<String, int> groupOrder = {
      for (int i = 0; i < downloadService.allGroups.length; i++)
        downloadService.allGroups[i]: i,
    };

    sorted.sort((a, b) {
      final int groupComparison =
          (groupOrder[a.group] ?? 9999).compareTo(groupOrder[b.group] ?? 9999);
      if (groupComparison != 0) {
        return groupComparison;
      }

      switch (state.sortBy) {
        case SortBy.manual:
          return compareDownloadManualOrder(
            firstOrder: a.sortOrder,
            secondOrder: b.sortOrder,
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

  List<GalleryDownloadInfo> reorderGalleriesInGroup(String group) {
    return sortedGalleries.where((gallery) => gallery.group == group).toList();
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
    await downloadService.updateGroupOrder(oldIndex, newIndex);
    updateSafely([bodyId]);
  }

  Future<void> saveGalleryOrderAfterReordered(
    String group,
    List<GalleryDownloadInfo> galleries,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex ||
        galleries.any((gallery) => gallery.group != group)) {
      return;
    }

    final List<GalleryDownloadInfo> reordered =
        reorderDownloadList(galleries, oldIndex, newIndex);
    for (int i = 0; i < reordered.length; i++) {
      reordered[i].sortOrder = i;
    }
    state.sortBy = SortBy.manual;
    updateSafely([bodyId]);
    await downloadService.updateGalleryOrder(reordered);
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
          configKey: ConfigEnum.displayGalleryGroups,
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
  void handleRemoveItem(GalleryDownloadInfo gallery, bool deleteImages,
      BuildContext context) async {
    bool confirmed = await confirmDestructiveAction(
        title: deleteImages
            ? 'deleteTaskAndImages'.tr + '?'
            : 'deleteTask'.tr + '?');
    if (!confirmed) {
      return;
    }

    bool isUpdatingDependent = downloadService.isUpdatingDependent(gallery.gid);

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
    }

    state.groupedListController.removeElement(gallery).then((_) {
      state.selectedGids.remove(gallery.gid);
      downloadService.deleteGallery(gallery, deleteImages: deleteImages);
      updateGlobalGalleryStatus();
    });
  }

  @override
  Future<void> selectAllItem() async {
    await state.displayGroupsCompleter.future;

    List<GalleryDownloadInfo> galleries = [];
    for (String group in state.displayGroups) {
      galleries.addAll(downloadService.galleriesWithGroup(group));
    }

    multiSelectDownloadPageState.selectedGids
        .addAll(galleries.map((gallery) => gallery.gid));
    updateSafely(multiSelectDownloadPageState.selectedGids
        .map((gid) => '$itemCardId::$gid')
        .toList());
  }
}
