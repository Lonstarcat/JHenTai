import 'package:dio/dio.dart';
import '../database/database.dart';
import '../model/download_batch_update.dart';
import '../model/download_multi_select_toolbar.dart';
import '../model/gallery_detail.dart';
import '../model/gallery_url.dart';
import '../network/eh_request.dart';
import '../utils/batch_update_control.dart';
import '../utils/convert_util.dart';
import '../utils/eh_spider_parser.dart';
import 'archive_download_service.dart';
import 'archive_quote_service.dart';
import 'background_task_service.dart';
import 'batch_update_background_bridge.dart';
import 'download_batch_update_service.dart';
import 'gallery_download/gallery_download_service.dart';
import 'log.dart';

ArchiveDownloadedData buildArchiveUpdateData(BatchUpdateSource source,
        GalleryDetail target, ArchiveUpdateQuote quote, DateTime now) =>
    ArchiveDownloadedData(
      gid: target.galleryUrl.gid,
      token: target.galleryUrl.token,
      title: target.japaneseTitle ?? target.rawTitle,
      category: target.category,
      pageCount: target.pageCount,
      galleryUrl: target.galleryUrl.url,
      coverUrl: target.cover.url,
      uploader: target.uploader,
      size: quote.sizeBytes,
      publishTime: target.publishTime,
      archiveStatusCode: ArchiveStatus.unlocking.code,
      archivePageUrl: target.archivePageUrl,
      isOriginal: source.original,
      insertTime: now.toString(),
      sortOrder: 0,
      groupName: source.group,
      tags: tagMap2TagString(target.tags),
      tagRefreshTime: now.toString(),
      parseSource: source.parseSource,
    );

class DownloadBatchUpdateBackend extends BatchUpdateBackend {
  final BatchUpdateRequestGate _requests = BatchUpdateRequestGate();
  final BatchArchiveSlot _archiveSlot = BatchArchiveSlot();
  int? _botBalance;

  @override
  void beginSession() => _botBalance = null;
  @override
  bool get globallyPaused => backgroundTaskService.isGloballyPaused;

  @override
  bool eligible(BatchUpdateSource source) {
    if (GalleryUrl.tryParse(source.galleryUrl)?.gid != source.gid) {
      return false;
    }
    if (source.kind == DownloadToolbarKind.gallery) {
      final old = galleryDownloadService.galleryDownloadInfos[source.gid];
      return old != null &&
          old.galleryUrl == source.galleryUrl &&
          old.downloadProgress.downloadStatus == DownloadStatus.downloaded &&
          !galleryDownloadService.isUpdatingDependent(source.gid);
    }
    final old = archiveDownloadService.archives
        .where((item) => item.gid == source.gid)
        .firstOrNull;
    return old != null &&
        archiveDownloadService
                .archiveDownloadInfos[source.gid]?.archiveStatus ==
            ArchiveStatus.completed &&
        old.galleryUrl == source.galleryUrl &&
        old.groupName == source.group &&
        old.isOriginal == source.original &&
        old.parseSource == source.parseSource;
  }

  @override
  bool exists(BatchUpdateSource source, int targetGid) =>
      source.kind == DownloadToolbarKind.gallery
          ? galleryDownloadService.containGallery(targetGid)
          : archiveDownloadService.containArchive(targetGid);

  Future<T> _read<T>(CancelToken cancel, Future<T> Function() request) async {
    for (int attempt = 0;; attempt++) {
      try {
        return await _requests.request(cancel, request);
      } on DioException catch (error) {
        if (attempt >= 1 ||
            cancel.isCancelled ||
            error.type == DioExceptionType.cancel) {
          rethrow;
        }
      }
    }
  }

  @override
  Future<GalleryDetail> detail(GalleryUrl url, CancelToken cancel) async {
    final response = await _read(
        cancel,
        () => ehRequest.requestDetailPage(
            galleryUrl: url.url,
            useCacheIfAvailable: false,
            cancelToken: cancel,
            parser: EHSpiderParser.detailPage2GalleryAndDetailAndApikey));
    return response.galleryDetails;
  }

  @override
  Future<ArchiveUpdateQuote?> quote(BatchUpdateSource source,
      GalleryDetail target, CancelToken cancel) async {
    if (source.kind == DownloadToolbarKind.gallery) {
      return null;
    }
    final archive = await _read(
        cancel,
        () => archiveQuoteService.official(target.archivePageUrl,
            cancelToken: cancel));
    final size = parseArchiveSizeBytes(
        source.original ? archive.originalSize : archive.resampleSize ?? '');
    if (size == null) {
      throw StateError('batchUpdateQuoteFailed');
    }
    if (source.parseSource == ArchiveParseSource.bot.code) {
      _botBalance ??= await _read(cancel, archiveQuoteService.botBalance);
      final cost = await _read(
          cancel,
          () => archiveQuoteService.botCost(
              target.galleryUrl.gid, target.galleryUrl.token));
      if (cost > _botBalance!) {
        throw StateError('batchUpdateInsufficientFunds');
      }
      return ArchiveUpdateQuote(
          sizeBytes: size,
          cost: '$cost GP',
          botGp: cost,
          botBalance: _botBalance);
    }
    final cost =
        source.original ? archive.originalCost : archive.resampleCost ?? '';
    if (!canAffordOfficialArchive(archive, source.original)) {
      throw StateError('batchUpdateInsufficientFunds');
    }
    if (!isKnownArchiveCost(cost)) {
      throw StateError('batchUpdateQuoteFailed');
    }
    return ArchiveUpdateQuote(sizeBytes: size, cost: cost);
  }

  @override
  Future<void> checkBudget(
      List<BatchUpdateItem> selected, CancelToken cancel) async {
    final botCost =
        selected.fold<int>(0, (sum, item) => sum + (item.quote?.botGp ?? 0));
    if (selected.any((item) => item.quote?.botGp != null)) {
      _botBalance = await _read(cancel, archiveQuoteService.botBalance);
      if (botCost > _botBalance!) {
        throw StateError('batchUpdateInsufficientFunds');
      }
    }
  }

  @override
  Future<void> waitForArchiveSlot(CancelToken cancel) =>
      _archiveSlot.wait(cancel);

  @override
  Future<UpdateSubmissionResult> submit(
      BatchUpdateItem item, CancelToken cancel) async {
    if (cancel.isCancelled || globallyPaused || !eligible(item.source)) {
      return const UpdateSubmissionResult(
          UpdateSubmissionStatus.failed, 'batchUpdateIneligible');
    }
    if (item.source.kind == DownloadToolbarKind.gallery) {
      return galleryDownloadService.submitGalleryUpdate(
          galleryDownloadService.galleryDownloadInfos[item.source.gid]!,
          item.target!,
          shouldProceed: () => !cancel.isCancelled && !globallyPaused);
    }
    final quote = item.quote!;
    final result = await archiveDownloadService.registerArchiveUpdate(
        buildArchiveUpdateData(
            item.source, item.target!, quote, DateTime.now()),
        shouldProceed: () =>
            !cancel.isCancelled && !globallyPaused && eligible(item.source));
    if (result.status == UpdateSubmissionStatus.submitted &&
        quote.botGp != null) {
      _botBalance = (_botBalance ?? 0) - quote.botGp!;
    }
    return result;
  }

  @override
  Future<void> runArchive(int gid) => _archiveSlot.run(() async {
        final cancelToken =
            archiveDownloadService.archiveDownloadInfos[gid]?.cancelToken;
        try {
          await archiveDownloadService.runRegisteredArchiveUpdate(gid);
        } catch (error, stack) {
          log.error('Batch archive pipeline stopped: $gid', error, stack);
          // A paused task replaces its cancel token. Do not let a stale failure
          // pause a new pipeline the user has explicitly resumed in the meantime.
          if (identical(
              archiveDownloadService.archiveDownloadInfos[gid]?.cancelToken,
              cancelToken)) {
            await archiveDownloadService.pauseDownloadArchive(gid);
          }
          rethrow;
        }
      });
}

final downloadBatchUpdateService = DownloadBatchUpdateService(
    DownloadBatchUpdateBackend(),
    backgroundProgress: batchUpdateBackgroundSnapshot);
