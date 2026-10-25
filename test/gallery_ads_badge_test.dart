import 'dart:collection';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/l18n/locale_text.dart';
import 'package:jhentai/src/model/gallery.dart';
import 'package:jhentai/src/model/gallery_image.dart';
import 'package:jhentai/src/model/gallery_tag.dart';
import 'package:jhentai/src/model/gallery_url.dart';
import 'package:jhentai/src/pages/download/grid/mixin/grid_download_page_mixin.dart';
import 'package:jhentai/src/setting/advanced_setting.dart';
import 'package:jhentai/src/setting/style_setting.dart';
import 'package:jhentai/src/service/super_resolution_service.dart';
import 'package:jhentai/src/service/read_progress_service.dart';
import 'package:jhentai/src/utils/gallery_badge_util.dart';
import 'package:jhentai/src/widget/eh_gallery_ads_badge.dart';
import 'package:jhentai/src/widget/eh_gallery_category_tag.dart';
import 'package:jhentai/src/widget/eh_gallery_list_card_.dart';
import 'package:jhentai/src/widget/eh_gallery_waterflow_card.dart';

const adsTag =
    TagData(namespace: 'other', key: 'extraneous ads', tagName: '广告');
const aiTag =
    TagData(namespace: 'other', key: 'ai generated', tagName: 'AI 生成');

class InMemoryReadProgress extends ReadProgressService {
  @override
  Future<int> getReadProgress(int gid) async => 0;
}

Gallery sampleGallery({bool ads = true, bool ai = false}) => Gallery(
      galleryUrl:
          GalleryUrl.parse('https://e-hentai.org/g/1234567/abcdef1234/'),
      title: 'Sample',
      category: 'Non-H',
      cover: GalleryImage(url: '', width: 150, height: 200),
      rating: 4,
      hasRated: false,
      publishTime: '2026-10-18 12:00',
      language: 'chinese',
      isExpunged: false,
      tags: LinkedHashMap.of({
        if (ads || ai)
          'other': [
            if (ads) GalleryTag(tagData: adsTag),
            if (ai) GalleryTag(tagData: aiTag),
          ],
      }),
    );

Widget host(Widget child,
        {Brightness brightness = Brightness.light, double scale = 1}) =>
    GetMaterialApp(
      translations: LocaleText(),
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.purple, brightness: brightness)),
      home: Scaffold(
          body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Center(
                  child: Column(
                      mainAxisSize: MainAxisSize.min, children: [child])))),
    );

void main() {
  setUp(() {
    final previousAds = styleSetting.showAdsBadge.value;
    final previousAi = styleSetting.showAiBadge.value;
    styleSetting.showAdsBadge.value = true;
    styleSetting.showAiBadge.value = true;
    addTearDown(() {
      styleSetting.showAdsBadge.value = previousAds;
      styleSetting.showAiBadge.value = previousAi;
    });
  });

  test('AI matches exact raw tags in maps, lists and stored metadata', () {
    expect(GalleryBadgeUtil.hasAiInMap(sampleGallery(ai: true).tags), isTrue);
    expect(GalleryBadgeUtil.hasAiInMap(sampleGallery().tags), isFalse);
    expect(GalleryBadgeUtil.hasAiInTags([aiTag, aiTag]), isTrue);
    expect(
        GalleryBadgeUtil.hasAiInTags([
          const TagData(namespace: 'artist', key: 'ai generated'),
          const TagData(
              namespace: 'other',
              key: 'not ai generated',
              tagName: 'ai generated'),
        ]),
        isFalse);
    expect(
        GalleryBadgeUtil.hasAiInString(
            'bad, : , other : ai generated ,artist:a'),
        isTrue);
    for (final tags in [
      null,
      '',
      'bad',
      'other:',
      'other:ai generated extra',
      'other:not ai generated',
      'other:AI generated',
      'artist:ai generated',
      'other:ai generated:bad'
    ]) {
      expect(GalleryBadgeUtil.hasAiInString(tags), isFalse, reason: '$tags');
    }
  });

  for (final ads in [false, true]) {
    for (final ai in [false, true]) {
      testWidgets('independent reactive switches and raw presence ($ads/$ai)',
          (tester) async {
        await tester.pumpWidget(host(EHGalleryCategoryWithAds(
            category: 'Non-H', hasAds: ads, hasAi: ai)));
        expect(find.byType(EHGalleryAdsBadge),
            ads ? findsOneWidget : findsNothing);
        expect(
            find.byType(EHGalleryAiBadge), ai ? findsOneWidget : findsNothing);
        styleSetting.showAdsBadge.value = false;
        await tester.pump();
        expect(find.byType(EHGalleryAdsBadge), findsNothing);
        expect(
            find.byType(EHGalleryAiBadge), ai ? findsOneWidget : findsNothing);
        styleSetting.showAiBadge.value = false;
        await tester.pump();
        expect(find.byType(EHGalleryAiBadge), findsNothing);
        expect(tester.getSize(find.byType(EHGalleryCategoryWithAds)),
            tester.getSize(find.byType(EHGalleryCategoryTag)));
      });
    }
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
          'both inline badges share category height and primary ($brightness/$scale)',
          (tester) async {
        await tester.pumpWidget(host(
            const EHGalleryCategoryWithAds(
                category: 'Non-H',
                hasAds: true,
                hasAi: true,
                useThemePrimary: true),
            brightness: brightness,
            scale: scale));
        final category = tester.getRect(find.byType(EHGalleryCategoryTag));
        final ads = tester.getRect(find.byType(EHGalleryAdsBadge));
        final ai = tester.getRect(find.byType(EHGalleryAiBadge));
        expect(ads.left, greaterThan(category.right));
        expect(ai.left, greaterThan(ads.right));
        expect(ai.height, closeTo(category.height, .1));
        expect(ai.top, ads.top);
        final context = tester.element(find.byType(EHGalleryAiBadge));
        expect(tester.widget<Text>(find.text('AI')).style!.color,
            Theme.of(context).colorScheme.primary);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('cover toggles remove all reserved space when disabled',
      (tester) async {
    await tester.pumpWidget(host(const EHGalleryCoverBadges(
        hasAds: true, hasAi: true, trailingSpacing: 4)));
    expect(find.byType(EHGalleryAdsBadge), findsOneWidget);
    expect(find.byType(EHGalleryAiBadge), findsOneWidget);
    styleSetting.showAdsBadge.value = false;
    await tester.pump();
    expect(find.byType(EHGalleryAdsBadge), findsNothing);
    expect(find.byType(EHGalleryAiBadge), findsOneWidget);
    styleSetting.showAiBadge.value = false;
    await tester.pump();
    expect(tester.getSize(find.byType(EHGalleryCoverBadges)), Size.zero);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'AI cover shares online and download badge colors ($brightness)',
        (tester) async {
      await tester.pumpWidget(host(
          const Row(mainAxisSize: MainAxisSize.min, children: [
            EHGalleryAiBadge.cover(useThemePrimary: true),
            EHGalleryAiBadge.cover(),
          ]),
          brightness: brightness));
      final context = tester.element(find.byType(EHGalleryAiBadge).first);
      final scheme = Theme.of(context).colorScheme;
      final text = tester.widgetList<Text>(find.text('AI')).toList();
      expect(text[0].style!.color, scheme.primary);
      expect(text[1].style!.color, scheme.onSurface);
    });
  }

  testWidgets(
      'narrow online footer retains both badges and existing indicators',
      (tester) async {
    final previousProgress = readProgressService;
    readProgressService = InMemoryReadProgress();
    Get.put<ReadProgressService>(readProgressService);
    addTearDown(() async {
      readProgressService = previousProgress;
      await Get.delete<ReadProgressService>();
    });
    advancedSetting.inNoImageMode.value = true;
    addTearDown(() => advancedSetting.inNoImageMode.value = false);
    final gallery = sampleGallery(ai: true)..pageCount = 42;
    gallery.favoriteTagIndex = 0;
    await tester.pumpWidget(host(SizedBox(
        width: 360,
        child: EHGalleryListCard(
            gallery: gallery,
            downloaded: true,
            listMode: ListMode.flatWithoutTags,
            withTags: false,
            handleTapCard: (_) {}))));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(EHGalleryAdsBadge), findsOneWidget);
    expect(find.byType(EHGalleryAiBadge), findsOneWidget);
    expect(find.text('42P'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [
    ListMode.waterfallFlowSmall,
    ListMode.waterfallFlowMedium,
    ListMode.waterfallFlowBig
  ]) {
    testWidgets('AI-only waterfall badge is not gated on Ads ($mode)',
        (tester) async {
      advancedSetting.inNoImageMode.value = true;
      addTearDown(() => advancedSetting.inNoImageMode.value = false);
      await tester.pumpWidget(host(SizedBox(
          width: 250,
          child: EHGalleryWaterFlowCard(
              gallery: sampleGallery(ads: false, ai: true),
              downloaded: false,
              listMode: mode,
              handleTapCard: (_) {}))));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(EHGalleryAdsBadge), findsNothing);
      expect(find.byType(EHGalleryAiBadge), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('exact raw map/tag matching ignores translations and other namespaces',
      () {
    expect(GalleryBadgeUtil.hasAdsInMap(sampleGallery().tags), isTrue);
    expect(
        GalleryBadgeUtil.hasAdsInMap(sampleGallery(ads: false).tags), isFalse);
    expect(GalleryBadgeUtil.hasAdsInTags([adsTag, adsTag]), isTrue);
    expect(
        GalleryBadgeUtil.hasAdsInTags([
          const TagData(namespace: 'female', key: 'extraneous ads'),
          const TagData(
              namespace: 'other',
              key: 'advertisement',
              tagName: 'extraneous ads'),
        ]),
        isFalse);
  });

  test(
      'download strings tolerate whitespace and broken entries, not substrings',
      () {
    expect(
        GalleryBadgeUtil.hasAdsInString(
            'bad, : , other : extraneous ads ,artist:a'),
        isTrue);
    for (final value in [
      null,
      '',
      'bad',
      'other:',
      'other:extraneous ads extra',
      'other:not extraneous ads',
      'female:extraneous ads',
      'other:extraneous ads:bad'
    ]) {
      expect(GalleryBadgeUtil.hasAdsInString(value), isFalse, reason: '$value');
    }
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('inline category height, text and theme: $brightness/$scale',
          (tester) async {
        await tester.pumpWidget(host(
            const EHGalleryCategoryWithAds(category: 'Non-H', hasAds: true),
            brightness: brightness,
            scale: scale));
        expect(find.text('广告'), findsOneWidget);
        expect(
            tester.getSize(find.byType(EHGalleryAdsBadge)).height,
            closeTo(
                tester.getSize(find.byType(EHGalleryCategoryTag)).height, 0.1));
        final text = tester.widget<Text>(find.text('广告'));
        final context = tester.element(find.byType(EHGalleryAdsBadge));
        expect(text.style!.color, Theme.of(context).colorScheme.primary);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('no ads means no extra spacing next to category', (tester) async {
    await tester.pumpWidget(
        host(const EHGalleryCategoryWithAds(category: 'Non-H', hasAds: false)));
    expect(find.byType(EHGalleryAdsBadge), findsNothing);
    expect(tester.getSize(find.byType(EHGalleryCategoryWithAds)),
        tester.getSize(find.byType(EHGalleryCategoryTag)));
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'online cover follows primary; download cover unchanged ($brightness)',
        (tester) async {
      await tester.pumpWidget(host(
          const Row(mainAxisSize: MainAxisSize.min, children: [
            EHGalleryAdsBadge.cover(useThemePrimary: true),
            EHGalleryAdsBadge.cover(),
          ]),
          brightness: brightness));
      final badges = find.byType(EHGalleryAdsBadge);
      final context = tester.element(badges.first);
      final scheme = Theme.of(context).colorScheme;
      final text = tester.widgetList<Text>(find.text('广告')).toList();
      expect(text[0].style!.color, scheme.primary);
      expect(text[1].style!.color, scheme.onSurface);
      final containers = tester
          .widgetList<Container>(
              find.descendant(of: badges, matching: find.byType(Container)))
          .toList();
      expect(
          ((containers[0].decoration as BoxDecoration).border as Border)
              .top
              .color,
          scheme.primary);
      expect(
          ((containers[1].decoration as BoxDecoration).border as Border)
              .top
              .color,
          scheme.onSurface);
    });
  }

  testWidgets(
      'grid cover badge matches original height and preserves tap/long/right-click',
      (tester) async {
    int taps = 0, longs = 0, rights = 0;
    await tester.pumpWidget(host(SizedBox(
        width: 220,
        height: 310,
        child: GridGallery(
          title: 'Sample',
          widget: const SizedBox.expand(child: ColoredBox(color: Colors.grey)),
          parseFromBot: true,
          isOriginal: true,
          hasAds: true,
          onTapWidget: () => taps++,
          onLongPress: (_) => longs++,
          onSecondTap: (_) => rights++,
        ))));
    final ads = find.byType(EHGalleryAdsBadge);
    final original = find
        .ancestor(of: find.text('原图'), matching: find.byType(Container))
        .first;
    expect(tester.getSize(ads).height, tester.getSize(original).height);
    expect(tester.getRect(ads).right, lessThan(tester.getRect(original).left));
    expect(find.byIcon(Icons.smart_toy_outlined), findsOneWidget);
    // Badge intentionally ignores pointers so the underlying card receives them.
    await tester.tapAt(tester.getCenter(ads));
    await tester.longPressAt(tester.getCenter(ads));
    final pointer = await tester.startGesture(tester.getCenter(ads),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await pointer.up();
    expect([taps, longs, rights], [1, 1, 1]);
    expect(tester.takeException(), isNull);
  });

  for (final bot in [false, true]) {
    testWidgets('150px grid keeps ads and right chips separate (bot=$bot)',
        (tester) async {
      await tester.pumpWidget(host(SizedBox(
          width: 150,
          height: 230,
          child: GridGallery(
            title: 'Sample',
            widget: const SizedBox.expand(),
            parseFromBot: bot,
            isOriginal: true,
            hasAds: true,
          ))));
      final ads = tester.getRect(find.byType(EHGalleryAdsBadge));
      final original = tester.getRect(find
          .ancestor(of: find.text('原图'), matching: find.byType(Container))
          .first);
      expect(ads.overlaps(original), isFalse);
      if (bot) {
        expect(
            ads.overlaps(tester.getRect(find.byIcon(Icons.smart_toy_outlined))),
            isFalse);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('narrow ads+bot+long AI+original chips reflow without overlap',
      (tester) async {
    const gid = 987654;
    final type = SuperResolutionType.values.first;
    superResolutionService.superResolutionInfoTable.put(
        gid,
        type,
        SuperResolutionInfo(type, SuperResolutionStatus.running,
            List.filled(10000, SuperResolutionStatus.success)));
    Get.put<SuperResolutionService>(superResolutionService);
    await tester.pumpWidget(host(SizedBox(
        width: 150,
        height: 230,
        child: GridGallery(
          title: 'Sample',
          widget: const SizedBox.expand(),
          parseFromBot: true,
          isOriginal: true,
          hasAds: true,
          hasAi: true,
          gid: gid,
          superResolutionType: type,
        ))));
    final ads = tester.getRect(find.byType(EHGalleryAdsBadge));
    final generated = tester.getRect(find.byType(EHGalleryAiBadge));
    final ai = tester.getRect(find.text('AI(10000/10000)'));
    final original = tester.getRect(find.text('原图'));
    final bot = tester.getRect(find.byIcon(Icons.smart_toy_outlined));
    expect(generated.top, greaterThan(ads.bottom));
    expect(generated.left, ads.left);
    expect(generated.overlaps(ai), isFalse);
    expect(generated.overlaps(original), isFalse);
    expect(generated.overlaps(bot), isFalse);
    expect(ads.overlaps(ai), isFalse);
    expect(ads.overlaps(original), isFalse);
    expect(ads.overlaps(bot), isFalse);
    expect(ai.overlaps(bot), isFalse);
    expect(ai.overlaps(original), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    superResolutionService.superResolutionInfoTable.remove(gid, type);
    await Get.delete<SuperResolutionService>();
  });

  for (final mode in [
    ListMode.flat,
    ListMode.flatWithoutTags,
    ListMode.listWithTags,
    ListMode.listWithoutTags
  ]) {
    testWidgets('online category badge in $mode even when tags hidden',
        (tester) async {
      advancedSetting.inNoImageMode.value = true;
      addTearDown(() => advancedSetting.inNoImageMode.value = false);
      await tester.pumpWidget(host(SizedBox(
          width: 600,
          child: EHGalleryListCard(
            gallery: sampleGallery(ai: true),
            downloaded: false,
            listMode: mode,
            withTags: false,
            handleTapCard: (_) {},
          ))));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(EHGalleryCategoryWithAds), findsOneWidget);
      expect(
          tester
              .widget<EHGalleryCategoryWithAds>(
                  find.byType(EHGalleryCategoryWithAds))
              .useThemePrimary,
          isTrue);
      expect(find.text('广告'), findsOneWidget);
      expect(find.byType(EHGalleryAiBadge), findsOneWidget);
      expect(tester.getRect(find.byType(EHGalleryAiBadge)).left,
          greaterThan(tester.getRect(find.byType(EHGalleryAdsBadge)).right));
      expect(tester.getRect(find.byType(EHGalleryAdsBadge)).left,
          greaterThan(tester.getRect(find.byType(EHGalleryCategoryTag)).right));
      expect(tester.takeException(), isNull);
    });
  }

  for (final mode in [
    ListMode.waterfallFlowSmall,
    ListMode.waterfallFlowMedium,
    ListMode.waterfallFlowBig
  ]) {
    testWidgets('waterfall $mode badge remains on cover bottom-left',
        (tester) async {
      advancedSetting.inNoImageMode.value = true;
      addTearDown(() => advancedSetting.inNoImageMode.value = false);
      await tester.pumpWidget(host(SizedBox(
          width: 250,
          child: EHGalleryWaterFlowCard(
            gallery: sampleGallery(ai: true),
            downloaded: false,
            listMode: mode,
            handleTapCard: (_) {},
          ))));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(EHGalleryAdsBadge), findsOneWidget);
      final adsRect = tester.getRect(find.byType(EHGalleryAdsBadge));
      final aiRect = tester.getRect(find.byType(EHGalleryAiBadge));
      expect(aiRect.top, greaterThan(adsRect.bottom));
      expect(aiRect.left, adsRect.left);
      expect(
          tester
              .widget<EHGalleryAdsBadge>(find.byType(EHGalleryAdsBadge))
              .useThemePrimary,
          isTrue);
      final positioned = tester.widget<Positioned>(find
          .ancestor(
              of: find.byType(EHGalleryAdsBadge),
              matching: find.byType(Positioned))
          .first);
      expect(positioned.left, 4);
      expect(positioned.bottom, 4);
      expect(tester.takeException(), isNull);
    });
  }
}
