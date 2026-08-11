import 'package:get/get.dart';
import 'package:jhentai/src/utils/toast_util.dart';

import '../../../../mixin/scroll_to_top_logic_mixin.dart';
import '../../../../service/local_gallery_service.dart';
import '../../download_reorder_mode.dart';
import 'grid_download_page_service_mixin.dart';
import 'grid_download_page_state_mixin.dart';

mixin GridBasePageLogic on GetxController
    implements Scroll2TopLogicMixin, DownloadReorderModeParticipant {
  final String bodyId = 'bodyId';
  final String galleryId = 'galleryId';
  final String editButtonId = 'editButtonId';

  GridBasePageState get gridBasePageState;

  GridBasePageServiceMixin get galleryService;

  @override
  void onClose() {
    unregisterDownloadReorderMode(this);
    super.onClose();
  }

  void enterGroup(String group) {
    gridBasePageState.currentGroup = group;
    update([bodyId]);
  }

  void backGroup() {
    gridBasePageState.currentGroup = LocalGalleryService.rootPath;
    update([bodyId, editButtonId]);
  }

  void toggleEditMode() {
    if (gridBasePageState.inEditMode) {
      exitEditMode();
      return;
    }
    if (!gridBasePageState.inEditMode) {
      toast('drag2sort'.tr);
    }
    gridBasePageState.inEditMode = true;
    registerDownloadReorderMode(this);
    update([bodyId, editButtonId]);
  }

  @override
  void exitEditMode() {
    if (!gridBasePageState.inEditMode) {
      return;
    }
    gridBasePageState.inEditMode = false;
    unregisterDownloadReorderMode(this);
    update([bodyId, editButtonId]);
  }

  Future<void> saveGalleryOrderAfterDrag(int beforeIndex, int afterIndex);

  Future<void> saveGroupOrderAfterDrag(int beforeIndex, int afterIndex);

  void handleResumeAllTasks();

  void handlePauseAllTasks();
}
