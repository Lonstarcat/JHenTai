import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/model/download_multi_select_toolbar.dart';
import 'package:jhentai/src/setting/style_setting.dart';
import 'package:jhentai/src/widget/download_multi_select_toolbar.dart';
import 'package:jhentai/src/widget/fade_slide_widget.dart';
import 'package:jhentai/src/widget/notification_overlay.dart';

import 'multi_select_download_page_logic_mixin.dart';
import 'multi_select_download_page_state_mixin.dart';

mixin MultiSelectDownloadPageMixin on StatelessWidget {
  MultiSelectDownloadPageLogicMixin get multiSelectDownloadPageLogic;

  MultiSelectDownloadPageStateMixin get multiSelectDownloadPageState;

  Widget buildBottomAppBar() {
    return GetBuilder<MultiSelectDownloadPageLogicMixin>(
      id: multiSelectDownloadPageLogic.bottomAppbarId,
      init: multiSelectDownloadPageLogic,
      global: false,
      builder: (_) => NotificationBottomBar(
          child: FadeSlideWidget(
        show: multiSelectDownloadPageState.inMultiSelectMode,
        axis: Axis.vertical,
        child: BottomAppBar(
          child: Obx(() => DownloadMultiSelectToolbar(
                config: styleSetting.toolbarConfig(toolbarKind).value,
                hasSelection:
                    multiSelectDownloadPageState.selectedGids.isNotEmpty,
                callbacks: buildToolbarCallbacks(),
                onClose: multiSelectDownloadPageLogic.exitSelectMode,
              )),
        ),
      )),
    );
  }

  DownloadToolbarKind get toolbarKind;

  Map<DownloadToolbarAction, VoidCallback> buildToolbarCallbacks();
}
