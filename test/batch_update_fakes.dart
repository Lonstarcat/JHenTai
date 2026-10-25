import 'dart:async';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:jhentai/src/model/download_batch_update.dart';
import 'package:jhentai/src/model/download_multi_select_toolbar.dart';
import 'package:jhentai/src/model/gallery_detail.dart';
import 'package:jhentai/src/model/gallery_image.dart';
import 'package:jhentai/src/model/gallery_url.dart';
import 'package:jhentai/src/service/download_batch_update_service.dart';
import 'package:jhentai/src/utils/batch_update_control.dart';

GalleryUrl testUrl(int gid) =>
    GalleryUrl(isEH: true, gid: gid, token: '0123456789');
BatchUpdateSource testSource(int gid, {bool archive = false}) =>
    BatchUpdateSource(
        kind:
            archive ? DownloadToolbarKind.archive : DownloadToolbarKind.gallery,
        gid: gid,
        title: 'Old $gid',
        galleryUrl: testUrl(gid).url,
        group: 'test group',
        original: true,
        parseSource: archive ? 1 : 0);

GalleryDetail testDetail(int gid, {int? next}) => GalleryDetail(
    galleryUrl: testUrl(gid),
    rawTitle: 'New $gid',
    category: 'Manga',
    cover: GalleryImage(url: 'https://example.invalid/cover.jpg'),
    pageCount: 10,
    rating: 4,
    realRating: 4,
    hasRated: false,
    ratingCount: 1,
    favoriteCount: 1,
    language: 'Japanese',
    publishTime: '2026-01-01',
    isExpunged: false,
    tags: LinkedHashMap(),
    size: '2 MB',
    torrentCount: '0',
    torrentPageUrl: 'https://example.invalid/torrent',
    archivePageUrl: 'https://example.invalid/archive/$gid',
    comments: [],
    thumbnails: [],
    thumbnailsPageCount: 1,
    childrenGalleries: next == null
        ? []
        : [
            (galleryUrl: testUrl(next), title: 'Next', updateTime: '2026-01-02')
          ]);

class FakeBatchBackend extends BatchUpdateBackend {
  final Map<int, GalleryDetail> details = {};
  final Set<int> excluded = {};
  final Set<int> existing = {};
  final Set<int> quoteFailures = {};
  final Set<int> submissionFailures = {};
  final List<int> reads = [];
  final List<int> submissions = [];
  final List<int> pipelines = [];
  Future<void> Function(int)? onRead;
  Completer<void>? pipelineGate;
  final BatchArchiveSlot slot = BatchArchiveSlot();
  bool priceChanged = false;
  bool budgetFailure = false;
  @override
  bool globallyPaused = false;
  @override
  void beginSession() {}
  @override
  bool eligible(BatchUpdateSource source) => !excluded.contains(source.gid);
  @override
  bool exists(BatchUpdateSource source, int gid) => existing.contains(gid);
  @override
  Future<GalleryDetail> detail(GalleryUrl url, CancelToken cancel) async {
    reads.add(url.gid);
    await onRead?.call(url.gid);
    return details[url.gid]!;
  }

  @override
  Future<ArchiveUpdateQuote?> quote(BatchUpdateSource source,
      GalleryDetail target, CancelToken cancel) async {
    if (source.kind == DownloadToolbarKind.gallery) {
      return null;
    }
    if (quoteFailures.contains(source.gid)) {
      throw StateError('batchUpdateQuoteFailed');
    }
    return ArchiveUpdateQuote(
        sizeBytes: 2048,
        cost: priceChanged ? '30 GP' : '20 GP',
        botGp: priceChanged ? 30 : 20,
        botBalance: 100);
  }

  @override
  Future<void> checkBudget(
      List<BatchUpdateItem> selected, CancelToken cancel) async {
    if (budgetFailure) {
      throw StateError('batchUpdateInsufficientFunds');
    }
  }

  @override
  Future<void> waitForArchiveSlot(CancelToken cancel) => slot.wait(cancel);
  @override
  Future<UpdateSubmissionResult> submit(
      BatchUpdateItem item, CancelToken cancel) async {
    submissions.add(item.target!.galleryUrl.gid);
    if (submissionFailures.contains(item.source.gid)) {
      return const UpdateSubmissionResult(UpdateSubmissionStatus.failed);
    }
    existing.add(item.target!.galleryUrl.gid);
    return const UpdateSubmissionResult(UpdateSubmissionStatus.submitted);
  }

  @override
  Future<void> runArchive(int gid) => slot.run(() async {
        pipelines.add(gid);
        await pipelineGate?.future;
      });
}
