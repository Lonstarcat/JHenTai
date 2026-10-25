import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/l18n/locale_text.dart';
import 'package:jhentai/src/model/gallery.dart';
import 'package:jhentai/src/model/jh_layout.dart';
import 'package:jhentai/src/setting/advanced_setting.dart';
import 'package:jhentai/src/setting/style_setting.dart';
import 'package:jhentai/src/utils/eh_spider_parser.dart';
import 'package:jhentai/src/utils/gallery_badge_util.dart';
import 'package:jhentai/src/widget/eh_cover_hero.dart';
import 'package:jhentai/src/widget/eh_gallery_ads_badge.dart';
import 'package:jhentai/src/widget/eh_gallery_waterflow_card.dart';
import 'package:jhentai/src/widget/eh_image.dart';

import 'gallery_ads_badge_test.dart' show host, sampleGallery;

void main() {
  setUp(() {
    final layout = styleSetting.actualLayout;
    final noImage = advancedSetting.inNoImageMode.value;
    final ads = styleSetting.showAdsBadge.value;
    final ai = styleSetting.showAiBadge.value;
    styleSetting.actualLayout = LayoutMode.mobileV2;
    advancedSetting.inNoImageMode.value = true;
    styleSetting.showAdsBadge.value = true;
    styleSetting.showAiBadge.value = true;
    addTearDown(() {
      styleSetting.actualLayout = layout;
      advancedSetting.inNoImageMode.value = noImage;
      styleSetting.showAdsBadge.value = ads;
      styleSetting.showAiBadge.value = ai;
    });
  });

  for (final mode in [
    ListMode.waterfallFlowSmall,
    ListMode.waterfallFlowMedium,
    ListMode.waterfallFlowBig,
  ]) {
    testWidgets('image-only push/pop hides and restores overlays ($mode)',
        (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final gallery = sampleGallery(ai: true);
      await tester.pumpWidget(GetMaterialApp(
        navigatorKey: navigator,
        translations: LocaleText(),
        locale: const Locale('zh', 'CN'),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              child: EHGalleryWaterFlowCard(
                gallery: gallery,
                downloaded: false,
                listMode: mode,
                handleTapCard: (_) {
                  navigator.currentState!.push(MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: Center(
                        child: EHImage(
                          galleryImage: gallery.cover,
                          heroTag: gallery.cover,
                          containerWidth: 150,
                          containerHeight: 200,
                        ),
                      ),
                    ),
                  ));
                },
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final originalBounds = tester.getRect(find.byType(EHCoverHero));
      expect(find.byType(EHGalleryAiBadge), findsOneWidget);
      expect(find.byType(EHGalleryAdsBadge), findsOneWidget);
      expect(find.byType(Hero), findsOneWidget); // no nested image Hero
      final image = tester.widget<EHImage>(find.byType(EHImage));
      expect(image.heroTag, isNull);

      await tester.tap(find.byType(EHGalleryWaterFlowCard));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(EHGalleryCoverBadges), findsNothing);
      expect(find.byType(EHGalleryAiBadge), findsNothing);
      expect(find.byType(EHGalleryAdsBadge), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();

      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(EHGalleryCoverBadges), findsNothing);
      expect(find.byType(EHGalleryAiBadge), findsNothing);
      expect(find.byType(EHGalleryAdsBadge), findsNothing);
      // The list-side shuttle contains only its EHImage, never the overlays.
      expect(
          find.byWidgetPredicate(
              (widget) => widget is EHImage && widget.heroTag == null),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.byType(EHGalleryAiBadge), findsOneWidget);
      expect(find.byType(EHGalleryAdsBadge), findsOneWidget);
      expect(tester.getRect(find.byType(EHCoverHero)), originalBounds);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('desktop and blocked covers retain overlays without Hero',
      (tester) async {
    for (final blocked in [false, true]) {
      styleSetting.actualLayout =
          blocked ? LayoutMode.mobileV2 : LayoutMode.desktop;
      final gallery = sampleGallery(ai: true)..blockedByLocalRules = blocked;
      await tester.pumpWidget(host(SizedBox(
        width: 240,
        child: EHGalleryWaterFlowCard(
          gallery: gallery,
          downloaded: false,
          listMode: ListMode.waterfallFlowSmall,
          handleTapCard: (_) {},
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.byType(Hero), findsNothing);
      expect(find.byType(EHGalleryAiBadge), findsOneWidget);
      expect(find.byType(EHGalleryAdsBadge), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('truncated rank tags stay unknown without requesting hydration',
      (tester) async {
    final parsed = EHSpiderParser.ranklistPage2GalleryPageInfo(
        Headers(),
        File('test/fixtures/ranklist_truncated_badges.html')
            .readAsStringSync());
    final gallery = (parsed.first as List).cast<Gallery>().single;
    expect(gallery.tags.values.expand((tags) => tags).length, 12);
    expect(GalleryBadgeUtil.hasAiInMap(gallery.tags), isFalse);
    expect(GalleryBadgeUtil.hasAdsInMap(gallery.tags), isFalse);
    await tester.pumpWidget(host(SizedBox(
      width: 240,
      child: EHGalleryWaterFlowCard(
        gallery: gallery,
        downloaded: false,
        listMode: ListMode.waterfallFlowSmall,
        handleTapCard: (_) {},
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(EHGalleryAiBadge), findsNothing);
    expect(find.byType(EHGalleryAdsBadge), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('badge widgets and page hooks have no hydration/network dependencies',
      () {
    for (final path in [
      'lib/src/widget/eh_gallery_ads_badge.dart',
      'lib/src/pages/base/base_page_logic.dart',
      'lib/src/pages/details/details_page_logic.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('galleryBadgeHydrationService')));
      expect(source, isNot(contains('gallery_badge_hydration_service')));
    }
    expect(
        File('lib/src/service/gallery_badge_hydration_service.dart')
            .existsSync(),
        isFalse);
  });
}
