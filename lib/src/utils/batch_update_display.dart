import '../model/download_batch_update.dart';
import '../model/download_multi_select_toolbar.dart';
import '../service/archive_quote_service.dart';

/// Display-only projection. Full service results and payment decisions stay intact.
bool isVisibleBatchUpdateItem(BatchUpdateItem item) =>
    item.target != null &&
    item.target!.galleryUrl.gid != item.source.gid &&
    switch (item.status) {
      BatchUpdateItemStatus.available ||
      BatchUpdateItemStatus.submitted ||
      BatchUpdateItemStatus.failed ||
      BatchUpdateItemStatus.cancelled =>
        true,
      _ => false,
    };

/// No Credits conversion: retain raw per-item quotes as the payment reference.
int? parseOfficialGp(String cost) {
  if (RegExp(r'^\s*free\s*$', caseSensitive: false).hasMatch(cost)) {
    return 0;
  }
  final match = RegExp(r'(?<![\d.,])(\d[\d,]*)\s*GP\b', caseSensitive: false)
      .firstMatch(cost);
  return match == null ? null : int.tryParse(match[1]!.replaceAll(',', ''));
}

class BatchUpdateDisplayStats {
  final int updateCount;
  final int sizeBytes;
  final int gp;
  final int botGp;
  final bool unknownSize;
  final bool unknownGp;
  const BatchUpdateDisplayStats(
      {required this.updateCount,
      required this.sizeBytes,
      required this.gp,
      required this.botGp,
      required this.unknownSize,
      required this.unknownGp});

  factory BatchUpdateDisplayStats.fromItems(Iterable<BatchUpdateItem> items) {
    int count = 0, bytes = 0, gp = 0, botGp = 0;
    bool unknownSize = false, unknownGp = false;
    for (final item in items.where(isVisibleBatchUpdateItem)) {
      if (!item.selected) {
        continue;
      }
      count++;
      final size =
          item.quote?.sizeBytes ?? parseArchiveSizeBytes(item.target!.size);
      if (size == null) {
        unknownSize = true;
      } else {
        bytes += size;
      }
      if (item.source.kind == DownloadToolbarKind.archive) {
        if (item.source.parseSource == 1) {
          botGp += item.quote?.botGp ?? 0;
        } else {
          final cost =
              item.quote == null ? null : parseOfficialGp(item.quote!.cost);
          if (cost == null) {
            unknownGp = true;
          } else {
            gp += cost;
          }
        }
      }
    }
    return BatchUpdateDisplayStats(
        updateCount: count,
        sizeBytes: bytes,
        gp: gp,
        botGp: botGp,
        unknownSize: unknownSize,
        unknownGp: unknownGp);
  }
}
