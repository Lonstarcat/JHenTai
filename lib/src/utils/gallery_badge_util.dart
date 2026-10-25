import '../database/database.dart';
import '../model/gallery_tag.dart';

/// Only raw tags are authoritative; translated names and titles are not evidence.
class GalleryBadgeUtil {
  static bool hasAdsInMap(Map<String, List<GalleryTag>> tags) => hasAdsInTags(
      tags.values.expand((group) => group.map((tag) => tag.tagData)));

  static bool hasAdsInTags(Iterable<TagData> tags) =>
      tags.any((tag) => _isAds(tag.namespace, tag.key));

  /// Tolerate malformed legacy entries without using the strict download parser.
  static bool hasAdsInString(String? tags) =>
      _hasTagInString(tags, 'extraneous ads');

  static bool hasAiInMap(Map<String, List<GalleryTag>> tags) => hasAiInTags(
      tags.values.expand((group) => group.map((tag) => tag.tagData)));

  static bool hasAiInTags(Iterable<TagData> tags) =>
      tags.any((tag) => _matches(tag.namespace, tag.key, 'ai generated'));

  static bool hasAiInString(String? tags) =>
      _hasTagInString(tags, 'ai generated');

  static bool _hasTagInString(String? tags, String expectedKey) {
    if (tags == null || tags.isEmpty) {
      return false;
    }
    return _hasRawTag(tags.split(','), expectedKey);
  }

  static bool _hasRawTag(Iterable<String> tags, String expectedKey) {
    return tags.any((tag) {
      final separator = tag.indexOf(':');
      return separator > 0 &&
          _matches(tag.substring(0, separator), tag.substring(separator + 1),
              expectedKey);
    });
  }

  static bool _isAds(String namespace, String key) =>
      _matches(namespace, key, 'extraneous ads');

  static bool _matches(String namespace, String key, String expectedKey) =>
      namespace.trim() == 'other' && key.trim() == expectedKey;
}
