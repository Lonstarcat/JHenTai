import 'dart:async';
import 'dart:convert';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../consts/eh_consts.dart';
import '../network/eh_request.dart';
import '../routes/routes.dart';
import '../setting/user_setting.dart';
import '../utils/cookie_util.dart';
import '../utils/forum_profile_parser.dart';
import 'path_service.dart';

/// Reuse existing WebView surfaces; challenges are completed by the user.
class ForumProfileWebview {
  static String _decode(Object? value) {
    if (value is! String) {
      return '';
    }
    try {
      final decoded = jsonDecode(value);
      return decoded is String ? decoded : value;
    } on FormatException {
      return value;
    }
  }

  /// Check ownership and actual URL after EVERY asynchronous DOM read.
  /// Separate from the platform adapter so logout-during-read is testable.
  static Future<Map<String, String?>?> readVerifiedDocument({
    required int id,
    required bool Function() current,
    required Future<bool> Function() onTarget,
    required Future<Object?> Function(String) evaluate,
  }) async {
    Future<bool> valid() async => current() && await onTarget() && current();
    if (!await valid()) {
      return null;
    }
    final html = _decode(await evaluate('document.documentElement.outerHTML'));
    if (!await valid()) {
      return null;
    }
    final profile = ForumProfileParser.parseProfile(html, memberId: id);
    if (profile == null) {
      return null;
    }
    final avatar = profile['avatarImgUrl'];
    if (avatar != null) {
      final bitmap = _decode(await evaluate('''
        (() => { try {
          const img = Array.from(document.images).find(i => i.src === ${jsonEncode(avatar)});
          if (!img || !img.complete || !img.naturalWidth) return "";
          const canvas = document.createElement('canvas');
          canvas.width = 128; canvas.height = 128;
          canvas.getContext('2d').drawImage(img, 0, 0, 128, 128);
          return canvas.toDataURL('image/png').split(',')[1] || "";
        } catch (_) { return ""; } })()
      '''));
      if (!await valid()) {
        return null;
      }
      if (bitmap.isNotEmpty && bitmap.length <= 1400000) {
        profile['avatarPng'] = bitmap;
      }
    }
    return await valid() ? profile : null;
  }

  static Future<Map<String, String?>?> read(
      int id, bool Function() current) async {
    final url = '${EHConsts.EForums}?showuser=$id';
    final account = userSetting;
    Map<String, String?>? result;
    bool reading = false;
    final marker = Object();
    bool target(String? value) {
      final uri = Uri.tryParse(value ?? '');
      return uri?.scheme == 'https' &&
          uri?.host == 'forums.e-hentai.org' &&
          uri?.queryParameters['showuser'] == '$id';
    }

    if (GetPlatform.isWindows || GetPlatform.isLinux) {
      if (!await WebviewWindow.isWebviewAvailable() || !current()) {
        return null;
      }
      final webview = await WebviewWindow.create(
          configuration: CreateConfiguration(
        windowWidth: 800,
        windowHeight: 600,
        title: 'forumAvatarVerification'.tr,
        userDataFolderWindows: pathService.getVisibleDir().path,
      ));
      if (!current()) {
        webview.close();
        return null;
      }
      final watcher = ever(account.avatarNeedsVerification, (_) {
        if (!current()) {
          webview.close();
        }
      });
      try {
        // Same forum-cookie verification mechanism as the upstream login flow.
        for (final cookie in ehRequest.cookies.where(
            (c) => c.name == 'ipb_member_id' || c.name == 'ipb_pass_hash')) {
          webview.addScriptToExecuteOnDocumentCreated(
              'if(location.protocol==="https:" && location.hostname==="forums.e-hentai.org") document.cookie=${jsonEncode('${cookie.name}=${cookie.value}; path=/; Secure')};');
        }
        Future<void> inspect() async {
          if (reading || !current()) {
            return;
          }
          reading = true;
          try {
            final parsed = await readVerifiedDocument(
                id: id,
                current: current,
                onTarget: () async => target(
                    _decode(await webview.evaluateJavaScript('location.href'))),
                evaluate: webview.evaluateJavaScript);
            if (parsed != null && current()) {
              result = parsed;
              webview.close();
            }
          } finally {
            reading = false;
          }
        }

        webview.isNavigating.addListener(() {
          if (!webview.isNavigating.value) {
            unawaited(inspect().catchError((Object _) {}));
          }
        });
        webview.launch(url);
        await webview.onClose;
      } finally {
        watcher.dispose();
      }
    } else {
      bool ownsRoute() =>
          Get.currentRoute == Routes.webview &&
          Get.arguments is Map &&
          identical(Get.arguments['forumProfileMarker'], marker);
      final watcher = ever(account.avatarNeedsVerification, (_) {
        if (!current() && ownsRoute()) {
          Get.back();
        }
      });
      try {
        await Get.toNamed(Routes.webview, preventDuplicates: false, arguments: {
          'title': 'forumAvatarVerification'.tr,
          'url': url,
          'cookies': CookieUtil.parse2String(ehRequest.cookies
              .where(
                  (c) => c.name == 'ipb_member_id' || c.name == 'ipb_pass_hash')
              .toList()),
          'forumProfileMarker': marker,
          'onPageFinished':
              (String location, WebViewController controller) async {
            if (reading || !current() || !ownsRoute() || !target(location)) {
              return;
            }
            reading = true;
            try {
              final parsed = await readVerifiedDocument(
                  id: id,
                  current: () => current() && ownsRoute(),
                  onTarget: () async => target(await controller.currentUrl()),
                  evaluate: controller.runJavaScriptReturningResult);
              if (parsed != null && current() && ownsRoute()) {
                result = parsed;
                Get.back();
              }
            } catch (_) {
              // Keep optional verification open; user cancellation is non-fatal.
            } finally {
              reading = false;
            }
          },
        });
      } finally {
        watcher.dispose();
      }
    }
    return current() ? result : null;
  }
}
