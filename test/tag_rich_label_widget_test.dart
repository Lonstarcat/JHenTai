import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart' show Value;
import 'package:extended_image/extended_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/l18n/locale_text.dart';
import 'package:jhentai/src/model/gallery_tag.dart';
import 'package:jhentai/src/setting/style_setting.dart';
import 'package:jhentai/src/widget/eh_gallery_waterflow_card.dart';
import 'package:jhentai/src/widget/eh_tag.dart';
import 'package:jhentai/src/widget/eh_tag_label.dart';

import 'tag_rich_label_parser_test.dart' show iconUrl;

const tag = TagData(
    namespace: 'parody',
    key: 'pokemon',
    tagName: '宝可梦🕊',
    fullTagName: '<p><img src="$iconUrl" alt="ball">宝可梦🕊</p>');

Widget host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  setUp(() => styleSetting.showTagIcons.value = false);
  tearDown(() => styleSetting.showTagIcons.value = false);

  test('new preference round-trips, missing/invalid key defaults off', () {
    final setting = StyleSetting();
    final Map<String, dynamic> config = jsonDecode(setting.toConfigString());
    config.remove('showTagIcons');
    setting.showTagIcons.value = true;
    setting.applyBeanConfig(jsonEncode(config));
    expect(setting.showTagIcons.value, isFalse);
    config['showTagIcons'] = 'true';
    setting.applyBeanConfig(jsonEncode(config));
    expect(setting.showTagIcons.value, isFalse);
    for (final value in [true, false]) {
      setting.showTagIcons.value = value;
      final restored = StyleSetting()
        ..applyBeanConfig(setting.toConfigString());
      expect(restored.showTagIcons.value, value);
    }
  });

  test('all locales include switch title and external-image notice', () {
    for (final values in LocaleText().keys.values) {
      expect(values['showTagIcons'], isNotEmpty);
      expect(values['showTagIconsHint'], isNotEmpty);
    }
  });

  testWidgets(
      'off keeps Emoji and vote suffix, on bounds icons and retains keys',
      (tester) async {
    Widget label(bool enabled) => EHTagLabel(
        tagData: tag,
        style: const TextStyle(fontSize: 12),
        showRichContent: enabled,
        maxIconSize: 999,
        suffix: '↑',
        imageBuilder: (image, size, fallback) =>
            SizedBox(key: const Key('icon'), width: size, height: size));
    await tester.pumpWidget(host(label(false)));
    expect(find.text('宝可梦🕊↑'), findsOneWidget);
    expect(find.byKey(const Key('icon')), findsNothing);
    await tester.pumpWidget(host(label(true)));
    expect(tester.getSize(find.byKey(const Key('icon'))), const Size(16, 16));
    expect(find.textContaining('宝可梦🕊', findRichText: true), findsWidgets);
    expect(tag.key, 'pokemon');
    expect(tag.namespace, 'parody');
    expect(tag.tagName, '宝可梦🕊');
  });

  testWidgets('image failure keeps adjacent text; image-only name has fallback',
      (tester) async {
    await tester.pumpWidget(host(EHTagLabel(
        tagData: tag,
        style: const TextStyle(fontSize: 12),
        showRichContent: true,
        imageBuilder: (_, size, fallback) => fallback)));
    expect(find.textContaining('宝可梦🕊', findRichText: true), findsWidgets);
    expect(find.text('ball'), findsNothing);
    const imageOnly = TagData(
        namespace: 'parody',
        key: 'fallback',
        fullTagName: '<img src="$iconUrl" alt="ball">');
    await tester.pumpWidget(host(EHTagLabel(
        tagData: imageOnly,
        style: const TextStyle(),
        showRichContent: true,
        imageBuilder: (_, size, fallback) => fallback)));
    expect(find.text('ball'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('production image has fixed bounds and offline fallback',
      (tester) async {
    await tester.pumpWidget(host(const EHTagLabel(
        tagData: tag, style: TextStyle(fontSize: 12), showRichContent: true)));
    final image = tester.widget<ExtendedImage>(find.byType(ExtendedImage));
    expect(image.width, 16);
    expect(image.height, 16);
    await tester.pump(const Duration(seconds: 6));
    expect(find.textContaining('宝可梦🕊', findRichText: true), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'slow production image stays mounted and displays a late successful response',
      (tester) async {
    final response = Completer<HttpClientResponse>();
    final client = _IconClient(response.future);
    final oldClientProvider = debugNetworkImageHttpClientProvider;
    debugNetworkImageHttpClientProvider = () => client;
    addTearDown(() => debugNetworkImageHttpClientProvider = oldClientProvider);
    // Unique URL avoids a previous test's memory cache. The bytes below are the
    // actual 13x13 WebP from the public translation database's pokemon icon.
    final slowTag = tag.copyWith(
        fullTagName: const Value('<p><img src="$iconUrl?test=slow">宝可梦</p>'));
    await tester.pumpWidget(host(EHTagLabel(
        tagData: slowTag,
        style: const TextStyle(fontSize: 12),
        showRichContent: true)));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(seconds: 16));
    expect(find.byType(ExtendedImage), findsOneWidget,
        reason: 'the display deadline must not dispose the provider');
    expect(client.requested?.host, 'raw.githubusercontent.com');
    expect(client.headers.names, isEmpty,
        reason: 'external icons must not receive EH credentials');
    response.complete(_IconResponse(base64Decode(
        'UklGRoYAAABXRUJQVlA4THkAAAAvDAADEBq3jSQ5zof3ITxFcAyHJsOhp07EMGuN27gULoYFKAEiARL/LzA6iyk0yQQspJFh8UVy+vR/AlQuEagJG+RaoMLxtp05kYSv7iK2MyfFv4N0PecEbEMBnClw+18YTgvi9SoYAxUviKiI1+sVEQOVEDFATUAlAA==')));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(
        (tester.state(find.byType(ExtendedImage)) as ExtendedImageState).extendedImageLoadState,
        LoadState.completed);
    expect(find.textContaining('宝可梦', findRichText: true), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    debugNetworkImageHttpClientProvider = oldClientProvider;
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'existing tag gestures, status and delete controls remain available',
      (tester) async {
    int taps = 0, secondary = 0, long = 0;
    final galleryTag = GalleryTag(
        tagData: tag,
        tagStatus: EHTagStatus.skepticism,
        voteStatus: EHTagVoteStatus.down);
    await tester.pumpWidget(host(EHTag(
        tag: galleryTag,
        useRichLabel: true,
        showTagStatus: true,
        inDeleteMode: true,
        onTap: (_) => taps++,
        onSecondaryTap: (_) => secondary++,
        onLongPress: (_) => long++)));
    await tester.tap(find.byType(EHTag));
    await tester.longPress(find.byType(EHTag));
    final gesture = await tester.startGesture(
        tester.getCenter(find.byType(EHTag)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton);
    await gesture.up();
    await tester.pumpAndSettle();
    expect([taps, secondary, long], [1, 1, 1]);
    expect(find.text('宝可梦🕊↓'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('search opt-out stays plain even with global switch on',
      (tester) async {
    styleSetting.showTagIcons.value = true;
    await tester.pumpWidget(
        host(EHTag(tag: GalleryTag(tagData: tag), useRichLabel: false)));
    expect(tester.widget<EHTagLabel>(find.byType(EHTagLabel)).showRichContent,
        isFalse);
    expect(find.text('宝可梦🕊'), findsOneWidget);
  });

  testWidgets(
      'open label reacts immediately; narrow waterfall fits without overflow',
      (tester) async {
    // No network request is needed to verify observation/layout (Emoji-only data).
    final emojiTag = tag.copyWith(fullTagName: const Value('<p>宝可梦🕊</p>'));
    await tester.pumpWidget(host(SizedBox(
        width: 90,
        child: EHTag(tag: GalleryTag(tagData: emojiTag), useRichLabel: true))));
    expect(tester.widget<EHTagLabel>(find.byType(EHTagLabel)).showRichContent,
        isFalse);
    styleSetting.showTagIcons.value = true;
    await tester.pump();
    expect(tester.widget<EHTagLabel>(find.byType(EHTagLabel)).showRichContent,
        isTrue);
    await tester.pumpWidget(host(SizedBox(
        width: 45,
        child: WaterFallFlowTag(galleryTag: GalleryTag(tagData: emojiTag)))));
    expect(tester.widget<EHTagLabel>(find.byType(EHTagLabel)).maxIconSize, 12);
    expect(tester.takeException(), isNull);
  });
}

/// Controlled HTTP response exercises the production provider/decoder without
/// contacting the public host or changing the application's global proxy.
class _IconClient extends Fake implements HttpClient {
  final Future<HttpClientResponse> response;
  final _IconHeaders headers = _IconHeaders();
  Uri? requested;
  _IconClient(this.response);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested = url;
    return _IconRequest(response, headers);
  }
}

class _IconRequest extends Fake implements HttpClientRequest {
  final Future<HttpClientResponse> response;
  @override
  final HttpHeaders headers;
  _IconRequest(this.response, this.headers);
  @override
  Future<HttpClientResponse> close() => response;
}

class _IconHeaders extends Fake implements HttpHeaders {
  final List<String> names = [];
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      names.add(name);
}

class _IconResponse extends Stream<List<int>> implements HttpClientResponse {
  final Uint8List bytes;
  _IconResponse(this.bytes);
  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(bytes).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
