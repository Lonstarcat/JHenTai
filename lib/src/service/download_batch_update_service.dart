import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../model/download_batch_update.dart';
import '../model/gallery_detail.dart';
import '../model/gallery_url.dart';
import '../model/download_multi_select_toolbar.dart';
import 'batch_update_background_bridge.dart';

abstract class BatchUpdateBackend {
  void beginSession();
  bool eligible(BatchUpdateSource source);
  bool exists(BatchUpdateSource source, int targetGid);
  bool get globallyPaused;
  Future<GalleryDetail> detail(GalleryUrl url, CancelToken cancel);
  Future<ArchiveUpdateQuote?> quote(
      BatchUpdateSource source, GalleryDetail target, CancelToken cancel);
  Future<void> checkBudget(List<BatchUpdateItem> selected, CancelToken cancel);
  Future<void> waitForArchiveSlot(CancelToken cancel);
  Future<UpdateSubmissionResult> submit(
      BatchUpdateItem item, CancelToken cancel);
  Future<void> runArchive(int gid);
}

/// Session lifetime is independent of the download page/controller. Only the
/// explicit confirm transition from review to submit can create paid tasks.
class DownloadBatchUpdateService extends ChangeNotifier {
  final BatchUpdateBackend backend;
  final Future<void> Function(Duration) sleep;
  final ValueNotifier<BatchUpdateBackgroundSnapshot?>? backgroundProgress;
  int _sessionId = 0;
  DownloadBatchUpdateService(this.backend,
      {Future<void> Function(Duration)? sleep, this.backgroundProgress})
      : sleep = sleep ?? Future<void>.delayed;
  BatchUpdatePhase phase = BatchUpdatePhase.idle;
  List<BatchUpdateItem> items = [];
  CancelToken _cancel = CancelToken();
  bool _executing = false;
  String? currentTitle;
  int current = 0;
  int total = 0;

  bool get active => _executing || phase == BatchUpdatePhase.review;
  DownloadToolbarKind? get sessionKind => items.firstOrNull?.source.kind;
  bool hasSessionFor(DownloadToolbarKind kind) =>
      phase != BatchUpdatePhase.idle && sessionKind == kind;
  int count(BatchUpdateItemStatus status) =>
      items.where((item) => item.status == status).length;
  int get stoppedCount => items
      .where((item) =>
          item.status == BatchUpdateItemStatus.submitted && item.reason != null)
      .length;
  int get selectedCount => items
      .where((item) =>
          item.selected && item.status == BatchUpdateItemStatus.available)
      .length;

  @override
  void notifyListeners() {
    final kind = sessionKind;
    if (backgroundProgress != null && kind != null) {
      backgroundProgress!.value = BatchUpdateBackgroundSnapshot(
          sessionId: _sessionId,
          kind: kind,
          phase: phase,
          currentTitle: currentTitle,
          current: current,
          total: total,
          available: count(BatchUpdateItemStatus.available),
          submitted: count(BatchUpdateItemStatus.submitted),
          failed: count(BatchUpdateItemStatus.failed),
          stopped: stoppedCount);
    }
    super.notifyListeners();
  }

  void select(BatchUpdateItem item, bool value) {
    if (phase == BatchUpdatePhase.review &&
        item.status == BatchUpdateItemStatus.available) {
      item.selected = value;
      notifyListeners();
    }
  }

  void cancel() {
    _cancel.cancel();
    if (!_executing) {
      _markCancelled();
      phase = BatchUpdatePhase.cancelled;
    }
    notifyListeners();
  }

  void _markCancelled() {
    for (final item in items) {
      if (item.status == BatchUpdateItemStatus.available ||
          (item.status == BatchUpdateItemStatus.skipped &&
              item.reason == null)) {
        item.status = BatchUpdateItemStatus.cancelled;
        item.selected = false;
      }
    }
  }

  Future<void> _checkpoint() async {
    while (backend.globallyPaused && !_cancel.isCancelled) {
      await sleep(const Duration(milliseconds: 200));
    }
    if (_cancel.isCancelled) {
      throw StateError('batchUpdateCancelled');
    }
  }

  Future<void> check(List<BatchUpdateSource> sources) async {
    if (active) {
      throw StateError('batchUpdateAlreadyRunning');
    }
    _executing = true;
    _cancel = CancelToken();
    _sessionId++;
    backend.beginSession();
    phase = BatchUpdatePhase.checking;
    items = sources.map(BatchUpdateItem.new).toList();
    current = 0;
    total = items.length;
    final targets = <int>{};
    notifyListeners();
    try {
      for (final item in items) {
        await _checkpoint();
        currentTitle = item.source.title;
        notifyListeners();
        try {
          if (!backend.eligible(item.source)) {
            item.reason = 'batchUpdateIneligible';
            continue;
          }
          final oldUrl = GalleryUrl.tryParse(item.source.galleryUrl);
          if (oldUrl == null) {
            throw StateError('batchUpdateInvalidVersion');
          }
          var detail = await backend.detail(oldUrl, _cancel);
          if (detail.galleryUrl.gid != oldUrl.gid) {
            throw StateError('batchUpdateInvalidVersion');
          }
          final visited = <int>{oldUrl.gid};
          while (detail.newVersionGalleryUrl != null) {
            await _checkpoint();
            final next = detail.newVersionGalleryUrl!;
            if (!visited.add(next.gid) || visited.length > 20) {
              throw StateError('batchUpdateInvalidVersion');
            }
            detail = await backend.detail(next, _cancel);
            if (detail.galleryUrl.gid != next.gid) {
              throw StateError('batchUpdateInvalidVersion');
            }
          }
          if (detail.galleryUrl.gid == item.source.gid) {
            item.status = BatchUpdateItemStatus.latest;
            continue;
          }
          item.target = detail;
          if (backend.exists(item.source, detail.galleryUrl.gid) ||
              targets.contains(detail.galleryUrl.gid)) {
            item.status = BatchUpdateItemStatus.existing;
            continue;
          }
          item.quote = await backend.quote(item.source, detail, _cancel);
          await _checkpoint();
          targets.add(detail.galleryUrl.gid);
          item.status = BatchUpdateItemStatus.available;
          item.selected = true;
        } catch (error) {
          if (_cancel.isCancelled) {
            break;
          }
          item.status = BatchUpdateItemStatus.failed;
          item.reason = _reason(error, 'batchUpdateCheckFailed');
        } finally {
          current++;
          notifyListeners();
        }
      }
      phase = _cancel.isCancelled
          ? BatchUpdatePhase.cancelled
          : BatchUpdatePhase.review;
      if (_cancel.isCancelled) {
        _markCancelled();
      }
    } catch (_) {
      _markCancelled();
      phase = BatchUpdatePhase.cancelled;
    } finally {
      _executing = false;
      currentTitle = null;
      notifyListeners();
    }
  }

  /// Cannot submit before discovery and explicit UI confirmation/checklist.
  Future<void> submit() async {
    if (_executing || phase != BatchUpdatePhase.review || _cancel.isCancelled) {
      throw StateError('batchUpdateAlreadyRunning');
    }
    final selected = items
        .where((item) =>
            item.selected && item.status == BatchUpdateItemStatus.available)
        .toList();
    _executing = true;
    phase = BatchUpdatePhase.submitting;
    current = 0;
    total = selected.length;
    notifyListeners();
    try {
      await _checkpoint();
      await backend.checkBudget(selected, _cancel);
      for (final item in selected) {
        await _checkpoint();
        currentTitle = item.source.title;
        notifyListeners();
        try {
          if (!backend.eligible(item.source)) {
            throw StateError('batchUpdateIneligible');
          }
          if (backend.exists(item.source, item.target!.galleryUrl.gid)) {
            item.status = BatchUpdateItemStatus.existing;
            continue;
          }
          if (item.quote != null) {
            await backend.waitForArchiveSlot(_cancel);
            await _checkpoint();
            // Long-running queues must not unlock using a stale, unapproved price.
            final fresh =
                await backend.quote(item.source, item.target!, _cancel);
            if (fresh == null || !item.quote!.sameTerms(fresh)) {
              throw StateError('batchUpdateQuoteChanged');
            }
          }
          await _checkpoint();
          final result = await backend.submit(item, _cancel);
          switch (result.status) {
            case UpdateSubmissionStatus.submitted:
              item.status = BatchUpdateItemStatus.submitted;
              if (item.quote != null) {
                // The Future remains owned by backend, even if this session is
                // cancelled. No rollback/delete of a potentially paid download.
                final pipeline =
                    backend.runArchive(item.target!.galleryUrl.gid);
                await Future.any([pipeline, _cancel.whenCancel]);
              }
            case UpdateSubmissionStatus.alreadyPresent:
              item.status = BatchUpdateItemStatus.existing;
            case UpdateSubmissionStatus.failed:
              item.status = BatchUpdateItemStatus.failed;
              item.reason = result.reason ?? 'batchUpdateRegistrationFailed';
          }
        } catch (error) {
          if (_cancel.isCancelled) {
            break;
          }
          if (item.status != BatchUpdateItemStatus.submitted) {
            item.status = BatchUpdateItemStatus.failed;
          }
          item.reason = _reason(error, 'batchUpdateSubmitFailed');
        } finally {
          current++;
          notifyListeners();
        }
      }
      phase = _cancel.isCancelled
          ? BatchUpdatePhase.cancelled
          : BatchUpdatePhase.finished;
    } catch (error) {
      if (!_cancel.isCancelled) {
        for (final item in selected
            .where((item) => item.status == BatchUpdateItemStatus.available)) {
          item.status = BatchUpdateItemStatus.failed;
          item.reason = _reason(error, 'batchUpdateSubmitFailed');
        }
      }
      phase = _cancel.isCancelled
          ? BatchUpdatePhase.cancelled
          : BatchUpdatePhase.finished;
    } finally {
      if (_cancel.isCancelled) {
        _markCancelled();
      }
      _executing = false;
      currentTitle = null;
      notifyListeners();
    }
  }

  String _reason(Object error, String fallback) =>
      error is StateError && error.message.startsWith('batchUpdate')
          ? error.message
          : fallback;

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }
}
