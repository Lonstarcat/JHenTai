import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages/layout/mobile_v2/mobile_layout_page_v2.dart';
import 'package:jhentai/src/service/forum_profile_service.dart';
import 'package:jhentai/src/service/forum_profile_webview.dart';
import 'package:jhentai/src/service/log.dart';
import 'package:jhentai/src/setting/user_setting.dart';
import 'package:jhentai/src/utils/forum_profile_parser.dart';

class QuietLog extends LogService {
  @override
  void debug(Object msg, [bool withStack = false]) {}
  @override
  void warning(Object msg, [Object? error, bool withStack = false]) {}
}

const profile = {
  'userName': 'User',
  'nickName': 'Nickname',
  'avatarImgUrl': 'https://forums.e-hentai.org/uploads/av-1.png',
  'avatarStatus': 'found',
};
const html =
    '''<div class="home"><b><a href="index.php?showuser=1">User</a></b></div>
<div><h2 id="profilename">Nickname</h2><div>Changed structure</div>
<section><img class="avatar" src="/uploads/av-1.png"></section></div>''';
final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jxXcAAAAASUVORK5CYII=');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UserSetting account;
  late LogService originalLog;
  setUp(() {
    originalLog = log;
    log = QuietLog();
    account = UserSetting(
        writeConfig: (_) async => 1, deleteConfig: () async => true);
  });
  tearDown(() {
    log = originalLog;
  });
  Future<void> login([int id = 1]) => account.saveUserInfo(
      userName: 'User$id', ipbMemberId: id, ipbPassHash: 'test-only');
  ForumProfileService service(
          {Future<Map<String, String?>?> Function(int)? fetch,
          Future<Uint8List> Function(String)? avatar,
          Future<Map<String, String?>?> Function(int, bool Function())?
              verify}) =>
      ForumProfileService(
        settings: () => account,
        fetchProfile: fetch ?? (_) async => profile,
        fetchAvatar: avatar ?? (_) async => png,
        prepareAvatar: (bytes) async => bytes,
        verifyProfile: verify,
      );

  test('profile parser survives changed siblings and resolves relative avatar',
      () {
    expect(ForumProfileParser.parseProfile(html, memberId: 1), profile);
    expect(ForumProfileParser.parseProfile(html, memberId: 2), isNull);
    expect(
        ForumProfileParser.parseProfile(html
            .replaceAll('class="avatar"', '')
            .replaceAll('/uploads/av-1.png', '/logo.png'))?['avatarImgUrl'],
        isNull);
    for (final bad in [
      '<html>broken',
      '<div class="pcen">$html</div>',
      '<div id="challenge-form"></div>$html',
      '<div id="userlinksguest"></div>$html'
    ]) {
      expect(ForumProfileParser.parseProfile(bad), isNull);
    }
  });

  test(
      'only trusted HTTPS avatar URLs; no placeholders, credentials or scripts',
      () {
    for (final bad in [
      '',
      'javascript:alert(1)',
      'data:image/png;base64,AA',
      'file:///avatar.png',
      'https://evil.test/av-1.png',
      'https://forums.e-hentai.org.evil.test/avatar.png',
      'https://u:p@forums.e-hentai.org/a.png',
      'http://forums.e-hentai.org/a.png',
      '/noavatar.png'
    ]) {
      expect(ForumProfileParser.avatarUrl(bad), isNull, reason: bad);
    }
    expect(ForumProfileParser.avatarUrl('//ehgt.org/avatars/1.png'),
        'https://ehgt.org/avatars/1.png');
  });

  test('concurrent calls and later calls fetch once per login', () async {
    await login();
    int calls = 0, images = 0;
    final response = Completer<Map<String, String?>?>();
    final s = service(fetch: (_) {
      calls++;
      return response.future;
    }, avatar: (_) async {
      images++;
      return png;
    });
    final first = s.ensureProfileForCurrentSession();
    final second = s.ensureProfileForCurrentSession();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    response.complete(profile);
    await Future.wait([first, second]);
    await s.ensureProfileForCurrentSession();
    expect([calls, images], [1, 1]);
    expect(account.avatarBytes.value, png);
    expect(account.nickName.value, 'Nickname');
  });

  test(
      'unknown avatar DOM keeps optional verification, explicit absence does not',
      () async {
    await login();
    final unknown = ForumProfileParser.parseProfile(html
        .replaceAll('class="avatar"', '')
        .replaceAll('/uploads/av-1.png', '/logo.png'))!;
    expect(unknown['avatarStatus'], 'unknown');
    final s = service();
    await s.ensureProfileForCurrentSession(profile: unknown);
    expect(s.needsVerification, isTrue);
    expect(account.nickName.value, 'Nickname');
    await account.clearBeanConfig();
    await login();
    final none = ForumProfileParser.parseProfile(
        html.replaceAll('/uploads/av-1.png', '/noavatar.png'))!;
    expect(none['avatarStatus'], 'none');
    await s.ensureProfileForCurrentSession(profile: none);
    expect(s.needsVerification, isFalse);
    expect(account.avatarBytes.value, isNull);
  });

  test(
      'image failure preserves authentication and parsed names; no automatic retry',
      () async {
    await login();
    int images = 0;
    final s = service(avatar: (_) async {
      images++;
      throw const FormatException('bad image');
    });
    await s.ensureProfileForCurrentSession();
    await s.ensureProfileForCurrentSession();
    expect(images, 1);
    expect(s.needsVerification, isTrue);
    expect(account.hasLoggedIn(), isTrue);
    expect(account.nickName.value, 'Nickname');
  });

  test(
      'new account verification is not locked by old session or its finally block',
      () async {
    await login();
    final a = Completer<Map<String, String?>?>();
    final b = Completer<Map<String, String?>?>();
    final calls = <int>[];
    final s = service(
        fetch: (_) async => null,
        verify: (id, _) {
          calls.add(id);
          return id == 1 ? a.future : b.future;
        });
    await s.ensureProfileForCurrentSession();
    final pendingA = s.verifyCurrentSession();
    s.invalidateSession();
    await account.clearBeanConfig();
    await login(2);
    await s.ensureProfileForCurrentSession();
    final pendingB = s.verifyCurrentSession();
    expect(calls, [1, 2]);
    a.complete(profile);
    await pendingA;
    await s.verifyCurrentSession();
    expect(
        calls, [1, 2]); // A's finally must not unlock B's active verification.
    b.complete({...profile, 'userName': 'B'});
    await pendingB;
    expect(account.userName.value, 'B');
    expect(account.avatarOwnerMemberId, 2);
  });

  for (final duringBitmap in [false, true]) {
    test(
        'WebView async DOM result discarded after account changes (bitmap=$duringBitmap)',
        () async {
      await login();
      final generation = account.profileGeneration;
      final read = Completer<Object?>();
      final started = Completer<void>();
      int bitmapReads = 0;
      final pending = ForumProfileWebview.readVerifiedDocument(
          id: 1,
          current: () => account.ownsProfileSession(1, generation),
          onTarget: () async => true,
          evaluate: (script) async {
            if (script == 'document.documentElement.outerHTML' && duringBitmap) {
              return html;
            }
            if (script != 'document.documentElement.outerHTML') {
              bitmapReads++;
            }
            started.complete();
            return read.future;
          });
      await started.future;
      await account.clearBeanConfig();
      await login(2);
      read.complete(duringBitmap ? base64Encode(png) : html);
      expect(await pending, isNull);
      expect(bitmapReads, duringBitmap ? 1 : 0);
    });
  }

  test('existing verified profile avoids a second forum fetch', () async {
    await login();
    int calls = 0;
    final s = service(fetch: (_) async {
      calls++;
      return profile;
    });
    await s.ensureProfileForCurrentSession(profile: profile);
    expect(calls, 0);
    expect(account.avatarBytes.value, png);
  });

  test('failure does not change authentication or automatically retry',
      () async {
    await login();
    int calls = 0;
    final s = service(fetch: (_) async {
      calls++;
      throw const FormatException('challenge');
    });
    await s.ensureProfileForCurrentSession();
    await s.ensureProfileForCurrentSession();
    expect(calls, 1);
    expect(s.needsVerification, isTrue);
    expect(account.hasLoggedIn(), isTrue);
    expect(account.avatarBytes.value, isNull);
  });

  test(
      'verification continuation can use WebView bitmap, no extra image request',
      () async {
    await login();
    int images = 0;
    final s = service(
        fetch: (_) async => null,
        avatar: (_) async {
          images++;
          return png;
        },
        verify: (_, current) async =>
            {...profile, 'avatarPng': base64Encode(png)});
    await s.ensureProfileForCurrentSession();
    await s.verifyCurrentSession();
    expect(images, 0);
    expect(account.avatarBytes.value, png);
    expect(s.needsVerification, isFalse);
  });

  test('cancelled verification remains optional and does not sign out',
      () async {
    await login();
    final s = service(fetch: (_) async => null, verify: (_, __) async => null);
    await s.ensureProfileForCurrentSession();
    await s.verifyCurrentSession();
    expect(account.hasLoggedIn(), isTrue);
    expect(s.needsVerification, isTrue);
  });

  test('pending web verification survives restart without automatic refetch',
      () async {
    await login();
    await service(fetch: (_) async => null).ensureProfileForCurrentSession();
    final saved = account.toConfigString();
    account =
        UserSetting(writeConfig: (_) async => 1, deleteConfig: () async => true)
          ..applyBeanConfig(saved);
    int calls = 0;
    final s = service(fetch: (_) async {
      calls++;
      return profile;
    });
    await s.ensureProfileForCurrentSession();
    expect(calls, 0);
    expect(s.needsVerification, isTrue);
  });

  test('Cloudflare background telemetry script is not itself a challenge', () {
    expect(
        ForumProfileParser.parseProfile(
            '$html<script src="/cdn-cgi/challenge-platform/scripts/jsd/main.js"></script>'),
        profile);
  });

  test(
      'restart restores account-owned image and attempted marker without requests',
      () async {
    await login();
    await service().ensureProfileForCurrentSession();
    final saved = account.toConfigString();
    account =
        UserSetting(writeConfig: (_) async => 1, deleteConfig: () async => true)
          ..applyBeanConfig(saved);
    int calls = 0;
    await service(fetch: (_) async {
      calls++;
      return profile;
    }).ensureProfileForCurrentSession();
    expect(calls, 0);
    expect(account.avatarBytes.value, png);
    expect(account.avatarOwnerMemberId, 1);
  });

  test(
      'wrong owner and corrupt optional cache never leak another account avatar',
      () async {
    await login();
    final config = jsonDecode(account.toConfigString()) as Map<String, dynamic>;
    account.applyBeanConfig(jsonEncode({
      ...config,
      'avatarOwnerMemberId': 2,
      'avatarBytes': base64Encode(png)
    }));
    expect(account.avatarBytes.value, isNull);
    account.applyBeanConfig(jsonEncode(
        {...config, 'avatarOwnerMemberId': 1, 'avatarBytes': 'not-base64%'}));
    expect(account.hasLoggedIn(), isTrue);
    expect(account.avatarBytes.value, isNull);
  });

  for (final switchAccount in [false, true]) {
    test(
        'logout/account switch during image transfer discards stale response ($switchAccount)',
        () async {
      await login();
      final response = Completer<Uint8List>();
      final started = Completer<void>();
      final s = service(avatar: (_) {
        started.complete();
        return response.future;
      });
      final pending = s.ensureProfileForCurrentSession();
      await started.future;
      s.invalidateSession();
      await account.clearBeanConfig();
      if (switchAccount) {
        await login(2);
      }
      response.complete(png);
      await pending;
      expect(account.avatarBytes.value, isNull);
      expect(account.nickName.value, isNull);
      expect(account.ipbMemberId.value, switchAccount ? 2 : null);
    });
  }

  test('same account relogin gets new avatar and no-avatar profile is valid',
      () async {
    await login();
    final s = service();
    await s.ensureProfileForCurrentSession();
    await account.clearBeanConfig();
    await login();
    await s.ensureProfileForCurrentSession(
        profile: {...profile, 'avatarImgUrl': null, 'avatarStatus': 'none'});
    expect(account.avatarBytes.value, isNull);
    expect(account.nickName.value, 'Nickname');
  });

  test(
      'all seven successful login paths use unified persistence and no stale profile callbacks',
      () {
    final source =
        File('lib/src/pages/setting/account/login/login_page_logic.dart')
            .readAsStringSync();
    expect('await _saveUserInfo('.allMatches(source).length, 7);
    expect(source, isNot(contains('saveUserNameAndAvatarAndNickName')));
    expect(source, contains('ensureProfileForCurrentSession'));
  });

  testWidgets(
      'sidebar displays only memory-backed current-session avatar, logout clears it',
      (tester) async {
    final original = userSetting;
    userSetting = account;
    addTearDown(() => userSetting = original);
    await tester.runAsync(() async {
      await login();
      await service().ensureProfileForCurrentSession();
    });
    await tester
        .pumpWidget(const GetMaterialApp(home: Scaffold(body: EHUserAvatar())));
    expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage,
        isA<MemoryImage>());
    await tester.runAsync(() => account.clearBeanConfig());
    await tester.pump();
    expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage,
        isNull);
    expect(tester.takeException(), isNull);
  });
}
