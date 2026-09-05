import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages/download/mixin/basic/multi_select/multi_select_download_page_mixin.dart';
import 'package:jhentai/src/pages/download/mixin/gallery/gallery_download_page_state_mixin.dart';
import 'package:jhentai/src/service/gallery_download/gallery_download_service.dart';

import '../../../../mixin/scroll_to_top_logic_mixin.dart';
import '../../../../mixin/scroll_to_top_page_mixin.dart';
import '../../../../mixin/scroll_to_top_state_mixin.dart';
import 'gallery_download_page_logic_mixin.dart';

mixin GalleryDownloadPageMixin on StatelessWidget
    implements Scroll2TopPageMixin, MultiSelectDownloadPageMixin {
  GalleryDownloadPageLogicMixin get galleryDownloadPageLogic;

  GalleryDownloadPageStateMixin get galleryDownloadPageState;

  @override
  Scroll2TopLogicMixin get scroll2TopLogic => galleryDownloadPageLogic;

  @override
  Scroll2TopStateMixin get scroll2TopState => galleryDownloadPageState;

  Widget buildDownloadFloatingActionButtons(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GetBuilder<GalleryDownloadService>(
          id: galleryDownloadPageLogic
              .downloadService.activeDownloadTaskChangedId,
          builder: (_) {
            final bool hasRunningTask =
                galleryDownloadPageLogic.runningDownloadTask != null;
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: hasRunningTask
                  ? Padding(
                      key: const ValueKey('locateRunningGalleryDownload'),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FloatingActionButton(
                        heroTag: null,
                        tooltip: 'locateRunningDownload'.tr,
                        onPressed: () => galleryDownloadPageLogic
                            .locateRunningDownloadTask(context),
                        child: const Icon(Icons.my_location),
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('noRunningGalleryDownload'),
                    ),
            );
          },
        ),
        buildFloatingActionButton(),
      ],
    );
  }

  @override
  List<Widget> buildBottomAppBarButtons() {
    return [
      IconButton(
          icon: const Icon(Icons.done_all),
          onPressed: galleryDownloadPageLogic.selectAllItem),
      IconButton(
          icon: const Icon(Icons.play_arrow),
          onPressed: galleryDownloadPageLogic.handleMultiResumeTasks),
      IconButton(
          icon: const Icon(Icons.pause),
          onPressed: galleryDownloadPageLogic.handleMultiPauseTasks),
      IconButton(
        tooltip: 'batchFavorite'.tr,
        icon: const Icon(Icons.favorite_outline),
        onPressed: multiSelectDownloadPageState.selectedGids.isEmpty
            ? null
            : galleryDownloadPageLogic.handleMultiFavoriteItems,
      ),
      IconButton(
          icon: const Icon(Icons.bookmark),
          onPressed: galleryDownloadPageLogic.handleMultiChangeGroup),
      IconButton(
          icon: const Icon(Icons.delete),
          onPressed: galleryDownloadPageLogic.handleMultiDelete),
      const Expanded(child: SizedBox()),
      IconButton(
          icon: const Icon(Icons.close),
          onPressed: multiSelectDownloadPageLogic.exitSelectMode),
    ];
  }
}
