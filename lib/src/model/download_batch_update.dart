import 'gallery_detail.dart';
import 'download_multi_select_toolbar.dart';

enum BatchUpdatePhase {
  idle,
  checking,
  review,
  submitting,
  finished,
  cancelled
}

enum BatchUpdateItemStatus {
  skipped,
  latest,
  existing,
  available,
  failed,
  submitted,
  cancelled
}

enum UpdateSubmissionStatus { submitted, alreadyPresent, failed }

class UpdateSubmissionResult {
  final UpdateSubmissionStatus status;
  final String? reason;
  const UpdateSubmissionResult(this.status, [this.reason]);
}

/// Snapshot of selection; live eligibility is checked again before submission.
class BatchUpdateSource {
  final DownloadToolbarKind kind;
  final int gid;
  final String title;
  final String galleryUrl;
  final String group;
  final bool original;
  final int parseSource;
  const BatchUpdateSource(
      {required this.kind,
      required this.gid,
      required this.title,
      required this.galleryUrl,
      required this.group,
      required this.original,
      this.parseSource = 0});
}

class ArchiveUpdateQuote {
  final int sizeBytes;
  final String cost;
  final int? botGp;
  final int? botBalance;
  const ArchiveUpdateQuote(
      {required this.sizeBytes,
      required this.cost,
      this.botGp,
      this.botBalance});

  bool sameTerms(ArchiveUpdateQuote other) =>
      sizeBytes == other.sizeBytes &&
      cost == other.cost &&
      botGp == other.botGp;
}

class BatchUpdateItem {
  final BatchUpdateSource source;
  BatchUpdateItemStatus status = BatchUpdateItemStatus.skipped;
  GalleryDetail? target;
  ArchiveUpdateQuote? quote;
  String? reason;
  bool selected = false;
  BatchUpdateItem(this.source);
}
