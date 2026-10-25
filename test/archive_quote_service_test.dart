import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/service/archive_quote_service.dart';
import 'package:jhentai/src/model/gallery_archive.dart';
import 'package:jhentai/src/service/download_batch_update_backend.dart';
import 'package:jhentai/src/model/download_batch_update.dart';
import 'batch_update_fakes.dart';

void main() {
  test('archive size supports known units and rejects malformed/unknown values',
      () {
    expect(parseArchiveSizeBytes(' 1.5 MiB '), 1572864);
    expect(parseArchiveSizeBytes('2 KB'), 2048);
    expect(parseArchiveSizeBytes('1 gib'), 1073741824);
    expect(parseArchiveSizeBytes('100 B'), 100);
    for (final value in [
      'N/A',
      '3 UNKNOWN',
      '-1 GB',
      '0 MB',
      'NaN',
      '1 TB extra'
    ]) {
      expect(parseArchiveSizeBytes(value), isNull);
    }
  });
  test('bot cost matches shared original formula with one-year boundary', () {
    final now = DateTime(2026, 10, 14);
    final posted = now.millisecondsSinceEpoch ~/ 1000;
    expect(computeArchiveBotCost(1000000, posted, now), 21);
    expect(computeArchiveBotCost(1000000, posted - 31536000, now), 21);
    expect(computeArchiveBotCost(1000000, posted - 31536001, now), 63);
  });
  test(
      'official quote validates free, unavailable resample and insufficient funds',
      () {
    final archive = GalleryArchive(
        originalCost: 'Free',
        originalSize: '1 MB',
        downloadOriginalHint: 'Download',
        downloadResampleHint: 'Unavailable');
    expect(canAffordOfficialArchive(archive, true), isTrue);
    expect(canAffordOfficialArchive(archive, false), isFalse);
    archive.downloadOriginalHint = 'Insufficient Funds';
    expect(canAffordOfficialArchive(archive, true), isFalse);
    expect(isKnownArchiveCost('1234 GP or 567 Credits'), isTrue);
    expect(isKnownArchiveCost('unknown'), isFalse);
  });
  test(
      'new archive refreshes target data, inherits preferences, never old URLs/path',
      () {
    final old = testSource(1, archive: true);
    final target = testDetail(11);
    final result = buildArchiveUpdateData(
        old,
        target,
        const ArchiveUpdateQuote(sizeBytes: 123, cost: '20 GP'),
        DateTime(2026));
    expect(result.gid, 11);
    expect(result.galleryUrl, target.galleryUrl.url);
    expect(result.title, 'New 11');
    expect(result.groupName, old.group);
    expect(result.isOriginal, old.original);
    expect(result.parseSource, old.parseSource);
    expect(result.size, 123);
    expect(result.downloadPageUrl, isNull);
    expect(result.downloadUrl, isNull);
    expect(result.sanitizedTitle, isNull);
    expect(old.gid, 1);
    expect(old.title, 'Old 1');
  });
}
