import 'dart:async';

import 'package:jhentai/src/mixin/scroll_to_top_state_mixin.dart';
import 'package:jhentai/src/pages/download/mixin/gallery/gallery_download_page_state_mixin.dart';

import '../../../../service/gallery_download/gallery_download_service.dart';
import '../../../../widget/grouped_list.dart';
import '../../mixin/basic/multi_select/multi_select_download_page_state_mixin.dart';
import '../widget/download_reorder_widgets.dart';

class GalleryListDownloadPageState
    with
        Scroll2TopStateMixin,
        GalleryDownloadPageStateMixin,
        MultiSelectDownloadPageStateMixin {
  Set<String> displayGroups = {};
  Completer<void> displayGroupsCompleter = Completer<void>();
  SortBy sortBy = SortBy.manual;
  bool inEditMode = false;
  final DownloadReorderExpansionSession reorderExpansionSession =
      DownloadReorderExpansionSession();

  final GroupedListController<String, GalleryDownloadInfo>
      groupedListController =
      GroupedListController<String, GalleryDownloadInfo>();
}

enum SortBy {
  manual('manual'),
  insertTime('insertTime'),
  title('title'),
  publishTime('publishTime');

  final String desc;
  const SortBy(this.desc);
}
