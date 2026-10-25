import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages/download/mixin/basic/multi_select/multi_select_download_page_mixin.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/model/download_multi_select_toolbar.dart';

import '../../../../mixin/scroll_to_top_logic_mixin.dart';
import '../../../../mixin/scroll_to_top_page_mixin.dart';
import '../../../../mixin/scroll_to_top_state_mixin.dart';
import '../basic/multi_select/multi_select_download_page_logic_mixin.dart';
import '../basic/multi_select/multi_select_download_page_state_mixin.dart';
import 'archive_download_page_logic_mixin.dart';
import 'archive_download_page_state_mixin.dart';

mixin ArchiveDownloadPageMixin on StatelessWidget
    implements Scroll2TopPageMixin, MultiSelectDownloadPageMixin {
  ArchiveDownloadPageLogicMixin get archiveDownloadPageLogic;

  ArchiveDownloadPageStateMixin get archiveDownloadPageState;

  @override
  Scroll2TopLogicMixin get scroll2TopLogic => archiveDownloadPageLogic;

  @override
  Scroll2TopStateMixin get scroll2TopState => archiveDownloadPageState;

  Widget buildDownloadFloatingActionButtons(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GetBuilder<ArchiveDownloadService>(
          id: ArchiveDownloadService.activeDownloadTaskChangedId,
          builder: (_) {
            final bool hasRunningTask =
                archiveDownloadPageLogic.runningDownloadTask != null;
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: hasRunningTask
                  ? Padding(
                      key: const ValueKey('locateRunningArchiveDownload'),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FloatingActionButton(
                        heroTag: null,
                        tooltip: 'locateRunningDownload'.tr,
                        onPressed: () => archiveDownloadPageLogic
                            .locateRunningDownloadTask(context),
                        child: const Icon(Icons.my_location),
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('noRunningArchiveDownload'),
                    ),
            );
          },
        ),
        buildFloatingActionButton(),
      ],
    );
  }

  @override
  MultiSelectDownloadPageLogicMixin get multiSelectDownloadPageLogic =>
      archiveDownloadPageLogic;

  @override
  MultiSelectDownloadPageStateMixin get multiSelectDownloadPageState =>
      archiveDownloadPageState;

  @override
  DownloadToolbarKind get toolbarKind => DownloadToolbarKind.archive;

  @override
  Map<DownloadToolbarAction, VoidCallback> buildToolbarCallbacks() => {
        DownloadToolbarAction.selectAll: archiveDownloadPageLogic.selectAllItem,
        DownloadToolbarAction.resume:
            archiveDownloadPageLogic.handleMultiResumeTasks,
        DownloadToolbarAction.pause:
            archiveDownloadPageLogic.handleMultiPauseTasks,
        DownloadToolbarAction.batchUpdate:
            archiveDownloadPageLogic.handleBatchUpdate,
        DownloadToolbarAction.favorite:
            archiveDownloadPageLogic.handleMultiFavoriteItems,
        DownloadToolbarAction.changeGroup:
            archiveDownloadPageLogic.handleMultiChangeGroup,
        DownloadToolbarAction.delete:
            archiveDownloadPageLogic.handleMultiDelete,
        DownloadToolbarAction.changeParseSource:
            archiveDownloadPageLogic.handleChangeParseSource,
      };
}
