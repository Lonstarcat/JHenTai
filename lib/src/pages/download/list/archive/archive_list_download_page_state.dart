import 'dart:async';

import 'package:jhentai/src/pages/download/mixin/basic/multi_select/multi_select_download_page_state_mixin.dart';

import '../../../../database/database.dart';
import '../../../../mixin/scroll_to_top_state_mixin.dart';
import '../../../../widget/grouped_list.dart';
import '../../mixin/archive/archive_download_page_state_mixin.dart';
import '../widget/download_reorder_widgets.dart';

class ArchiveListDownloadPageState
    with
        Scroll2TopStateMixin,
        MultiSelectDownloadPageStateMixin,
        ArchiveDownloadPageStateMixin {
  Set<String> displayGroups = {};
  Completer<void> displayGroupsCompleter = Completer<void>();
  SortBy sortBy = SortBy.manual;
  bool inEditMode = false;
  final DownloadReorderExpansionSession reorderExpansionSession =
      DownloadReorderExpansionSession();

  final GroupedListController<String, ArchiveDownloadedData>
      groupedListController =
      GroupedListController<String, ArchiveDownloadedData>();
}

enum SortBy {
  manual('Manual'),
  insertTime('Insert Time'),
  title('Title'),
  publishTime('Publish Time');

  final String label;
  const SortBy(this.label);
}
