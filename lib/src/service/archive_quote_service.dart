import 'package:dio/dio.dart';
import '../model/gallery_archive.dart';
import '../network/eh_request.dart';
import '../network/eh_cache_manager.dart';
import '../network/archive_bot_request.dart';
import '../setting/archive_bot_setting.dart';
import '../utils/eh_spider_parser.dart';

int? parseArchiveSizeBytes(String text) {
  final match =
      RegExp(r'^\s*(\d+(?:\.\d+)?)\s*(B|[KMGT]i?B)\s*$', caseSensitive: false)
          .firstMatch(text);
  if (match == null) {
    return null;
  }
  final value = double.parse(match[1]!);
  final unit = match[2]!.toUpperCase();
  final exponent = unit == 'B' ? 0 : 'KMGT'.indexOf(unit[0]) + 1;
  double bytes = value;
  for (int i = 0; i < exponent; i++) {
    bytes *= 1024;
  }
  return bytes.isFinite && bytes > 0 ? bytes.toInt() : null;
}

int computeArchiveBotCost(int filesize, int posted, DateTime now) {
  final multiplier =
      now.millisecondsSinceEpoch ~/ 1000 - posted > 31536000 ? 3 : 1;
  return ((filesize / 1e6 * 20).toInt() + 1) * multiplier;
}

bool canAffordOfficialArchive(GalleryArchive archive, bool original) {
  final cost = original ? archive.originalCost : archive.resampleCost;
  final size = original ? archive.originalSize : archive.resampleSize;
  final hint =
      original ? archive.downloadOriginalHint : archive.downloadResampleHint;
  return size != null &&
      parseArchiveSizeBytes(size) != null &&
      cost != null &&
      cost.trim().isNotEmpty &&
      cost != 'N/A' &&
      !hint.toLowerCase().contains('insufficient funds');
}

bool isKnownArchiveCost(String text) =>
    RegExp(r'free|\d+\s*(?:GP|Credits?)', caseSensitive: false).hasMatch(text);

class ArchiveQuoteService {
  Future<GalleryArchive> official(String url, {CancelToken? cancelToken}) =>
      ehRequest.get(
          url: url,
          cancelToken: cancelToken,
          options: CacheOptions.noCacheOptions.toOptions(),
          parser: EHSpiderParser.archivePage2Archive);

  Future<int> botCost(int gid, String token) async {
    final metadata = await ehRequest.requestGalleryMetadata(
        gid: gid,
        token: token,
        parser: EHSpiderParser.galleryMetadataJson2FileSizeAndPosted);
    return computeArchiveBotCost(
        metadata.filesize, metadata.posted, DateTime.now());
  }

  Future<int> botBalance() async {
    if (!archiveBotSetting.isReady) {
      throw StateError('archiveBotNotConfigured');
    }
    final response = await archiveBotRequest.requestBalance(
        botType: archiveBotSetting.botType.value,
        apiAddress: archiveBotSetting.apiAddress.value!,
        apiKey: archiveBotSetting.apiKey.value!);
    if (!response.isSuccess) {
      throw StateError('checkBalanceFailed');
    }
    return archiveBotSetting.botType.value.parseBalance(response.data).gp;
  }
}

final archiveQuoteService = ArchiveQuoteService();
