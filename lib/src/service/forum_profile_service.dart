import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;

import '../network/eh_request.dart';
import '../setting/user_setting.dart';
import '../utils/forum_profile_parser.dart';
import 'forum_profile_webview.dart';
import 'log.dart';

final forumProfileService = ForumProfileService();

/// Optional profile work belongs to an authenticated session, not a login page.
class ForumProfileService {
  final UserSetting Function() settings;
  final Future<Map<String, String?>?> Function(int) fetchProfile;
  final Future<Uint8List> Function(String) fetchAvatar;
  final Future<Uint8List> Function(Uint8List) prepareAvatar;
  final Future<Map<String, String?>?> Function(int, bool Function())
      verifyProfile;
  String? _verifyingKey;
  Future<void>? _inFlight;
  String? _inFlightKey;

  ForumProfileService({
    UserSetting Function()? settings,
    Future<Map<String, String?>?> Function(int)? fetchProfile,
    Future<Uint8List> Function(String)? fetchAvatar,
    Future<Uint8List> Function(Uint8List)? prepareAvatar,
    Future<Map<String, String?>?> Function(int, bool Function())? verifyProfile,
  })  : settings = settings ?? (() => userSetting),
        fetchProfile = fetchProfile ??
            ((id) => ehRequest.requestForum(
                id,
                (_, data) => data is String
                    ? ForumProfileParser.parseProfile(data, memberId: id)
                    : null)),
        fetchAvatar =
            fetchAvatar ?? ((url) => ehRequest.requestForumAvatar(url)),
        prepareAvatar = prepareAvatar ?? _prepareAvatar,
        verifyProfile = verifyProfile ?? ForumProfileWebview.read;

  String get _key =>
      '${settings().ipbMemberId.value}:${settings().profileGeneration}';
  bool get needsVerification =>
      settings().hasLoggedIn() && settings().avatarNeedsVerification.value;

  Future<void> ensureProfileForCurrentSession({Map<String, String?>? profile}) {
    final account = settings();
    if (!account.hasLoggedIn()) {
      return Future.value();
    }
    if (_inFlightKey == _key && _inFlight != null) {
      return _inFlight!;
    }
    if (account.avatarLookupAttempted) {
      return Future.value();
    }
    final id = account.ipbMemberId.value!;
    final generation = account.profileGeneration;
    account.avatarLookupAttempted = true;
    _inFlightKey = _key;
    account.avatarNeedsVerification.value = false;
    return _inFlight = _acquire(account, id, generation, profile);
  }

  Future<void> _acquire(UserSetting account, int id, int generation,
      Map<String, String?>? profile) async {
    bool current() =>
        identical(account, settings()) &&
        account.ownsProfileSession(id, generation);
    try {
      await account.saveBeanConfig();
      if (!current()) {
        return;
      }
      final result = profile ?? await fetchProfile(id);
      if (!current()) {
        return;
      }
      if (result == null) {
        account.avatarNeedsVerification.value = true;
        await account.saveBeanConfig();
        return;
      }
      await _store(account, id, generation, result, current);
    } catch (error) {
      if (current()) {
        account.avatarNeedsVerification.value = true;
        try {
          await account.saveBeanConfig();
        } catch (_) {
          // Keep the optional verification affordance usable if storage fails.
        }
        // Never log response HTML, avatar bytes, cookies or authentication hashes.
        log.warning(
            'Forum profile unavailable (${error.runtimeType}); web verification available');
      }
    }
  }

  Future<void> _store(UserSetting account, int id, int generation,
      Map<String, String?> profile, bool Function() current) async {
    final username = profile['userName'];
    final nickname = profile['nickName'];
    if (username == null ||
        username.isEmpty ||
        nickname == null ||
        nickname.isEmpty) {
      return;
    }
    final url = ForumProfileParser.avatarUrl(profile['avatarImgUrl']);
    Uint8List? bytes;
    bool needsVerification = url == null && profile['avatarStatus'] != 'none';
    if (url != null) {
      try {
        // A verified same-origin WebView may provide the already loaded bitmap.
        final embedded = profile['avatarPng'];
        bytes = await prepareAvatar(
            embedded != null && embedded.length <= 1400000
                ? base64Decode(embedded)
                : await fetchAvatar(url));
      } catch (error) {
        needsVerification = true;
        log.warning('Forum avatar unavailable (${error.runtimeType})');
      }
    }
    if (!current()) {
      return;
    }
    await account.saveForumProfile(
        memberId: id,
        generation: generation,
        userName: username,
        nickName: nickname,
        avatarImgUrl: url,
        bytes: bytes,
        needsVerification: needsVerification);
  }

  /// User-initiated continuation of the same acquisition; no automatic retry loop.
  Future<void> verifyCurrentSession() async {
    if (!needsVerification || _verifyingKey == _key) {
      return;
    }
    final verificationKey = _key;
    _verifyingKey = verificationKey;
    final account = settings();
    final id = account.ipbMemberId.value!;
    final generation = account.profileGeneration;
    bool current() =>
        identical(account, settings()) &&
        account.ownsProfileSession(id, generation);
    try {
      final profile = await verifyProfile(id, current);
      if (profile != null && current()) {
        await _store(account, id, generation, profile, current);
      }
    } catch (error) {
      log.warning(
          'Forum profile verification incomplete (${error.runtimeType})');
    } finally {
      if (_verifyingKey == verificationKey) {
        _verifyingKey = null;
      }
    }
  }

  void invalidateSession() {
    settings().invalidateProfileSession();
    _inFlightKey = null;
    _inFlight = null;
    _verifyingKey = null;
  }

  static Future<Uint8List> _prepareAvatar(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 1024 * 1024) {
      throw const FormatException('Invalid avatar size');
    }
    final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: 128, targetHeight: 128);
    try {
      final frame = await codec.getNextFrame();
      try {
        final png =
            await frame.image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) {
          throw const FormatException('Invalid avatar image');
        }
        return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
