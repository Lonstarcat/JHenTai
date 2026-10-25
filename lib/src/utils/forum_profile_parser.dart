import 'package:html/parser.dart';

/// Never treat a challenge/guest/error page or an unrelated site image as profile data.
class ForumProfileParser {
  static const forumUrl = 'https://forums.e-hentai.org/index.php';

  static String? avatarUrl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final relative = Uri.tryParse(value.trim());
    if (relative == null) {
      return null;
    }
    final uri = Uri.parse(forumUrl).resolveUri(relative);
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        (uri.host != 'forums.e-hentai.org' &&
            uri.host != 'ehgt.org' &&
            !uri.host.endsWith('.ehgt.org'))) {
      return null;
    }
    if (['noavatar', 'no_avatar', 'default_avatar', 'default-avatar']
        .any(uri.path.contains)) {
      return null;
    }
    return uri.toString();
  }

  static Map<String, String?>? parseProfile(String html, {int? memberId}) {
    final document = parse(html);
    if (document.querySelector(
            '.pcen, #userlinksguest, #challenge-form, #cf-challenge-running') !=
        null) {
      return null;
    }
    final profile = document.querySelector('#profilename');
    final account = document.querySelector('.home > b > a');
    final name = account?.text.trim();
    final nickname = profile?.text.trim();
    if (profile == null ||
        name == null ||
        name.isEmpty ||
        nickname == null ||
        nickname.isEmpty) {
      return null;
    }
    final accountId = Uri.tryParse(account!.attributes['href'] ?? '')
        ?.queryParameters['showuser'];
    if (memberId != null &&
        accountId != null &&
        accountId != memberId.toString()) {
      return null;
    }
    final candidates = [
      ...document.querySelectorAll(
          '#profile-avatar img, #profile_photo, img.avatar, img[src*="uploads/av-"], img[src*="/avatars/"]'),
      ...?profile.parent?.querySelectorAll(
          'img[src*="avatar"], img[src*="uploads/av-"], img[alt="Avatar"]'),
    ];
    String? avatar;
    for (final image in candidates) {
      avatar = avatarUrl(image.attributes['src']);
      if (avatar != null) {
        break;
      }
    }
    final noAvatar = document.querySelector(
            'img[src*="noavatar"], img[src*="no_avatar"], img[src*="default_avatar"], img[src*="default-avatar"], .no-avatar, .noavatar') !=
        null;
    return {
      'userName': name,
      'nickName': nickname,
      'avatarImgUrl': avatar,
      'avatarStatus': avatar != null
          ? 'found'
          : noAvatar
              ? 'none'
              : 'unknown',
    };
  }
}
