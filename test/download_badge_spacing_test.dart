import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/l18n/locale_text.dart';
import 'package:jhentai/src/setting/style_setting.dart';
import 'package:jhentai/src/widget/eh_gallery_ads_badge.dart';
import 'package:jhentai/src/widget/eh_gallery_category_tag.dart';

Rect bounds(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return Rect.fromPoints(box.localToGlobal(Offset.zero),
      box.localToGlobal(box.size.bottomRight(Offset.zero)));
}

void main() {
  setUp(() {
    final ads = styleSetting.showAdsBadge.value;
    final ai = styleSetting.showAiBadge.value;
    styleSetting.showAdsBadge.value = true;
    styleSetting.showAiBadge.value = true;
    addTearDown(() {
      styleSetting.showAdsBadge.value = ads;
      styleSetting.showAiBadge.value = ai;
    });
  });

  for (final category in ['Manga', 'Doujinshi']) {
    for (final inset in [0.0, 6.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final narrow in [false, true]) {
          testWidgets(
              '$category inset $inset scale $scale narrow $narrow keeps anchors and left-adjacent badges',
              (tester) async {
            Rect? categoryAnchor;
            Rect? originalAnchor;
            for (final flags in [
              (false, false),
              (true, false),
              (false, true),
              (true, true)
            ]) {
              await tester.pumpWidget(GetMaterialApp(
                locale: const Locale('zh', 'CN'),
                translations: LocaleText(),
                home: Scaffold(
                    body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Center(
                      child: SizedBox(
                          // Ahem has fixed-width glyphs. Keep the unchanged
                          // category and controls visible, but constrain the
                          // remaining badge area to exercise scale-down.
                          width: narrow
                              ? category.length * 15 * scale + 140
                              : scale == 1
                                  ? 280
                                  : scale == 1.5
                                      ? 360
                                      : 420,
                          child: Row(children: [
                            Expanded(
                                child: EHDownloadCategoryWithBadges(
                                    category: category,
                                    hasAds: flags.$1,
                                    hasAi: flags.$2,
                                    trailingInset: inset)),
                            Padding(
                                padding: EdgeInsets.only(left: inset, right: 6),
                                child: Container(
                                    key: const ValueKey('original'),
                                    width: 24,
                                    height: 20,
                                    decoration:
                                        BoxDecoration(border: Border.all()),
                                    child: const Text('原图',
                                        style: TextStyle(fontSize: 9)))),
                            const SizedBox(width: 70),
                          ]))),
                )),
              ));
              final categoryRect =
                  bounds(tester, find.byType(EHGalleryCategoryTag));
              final originalRect =
                  bounds(tester, find.byKey(const ValueKey('original')));
              categoryAnchor ??= categoryRect;
              originalAnchor ??= originalRect;
              expect(categoryRect, categoryAnchor);
              expect(originalRect, originalAnchor);
              Rect? badges;
              if (flags.$1) {
                badges = bounds(tester, find.byType(EHGalleryAdsBadge));
              }
              if (flags.$2) {
                final ai = bounds(tester, find.byType(EHGalleryAiBadge));
                badges = badges?.expandToInclude(ai) ?? ai;
              }
              if (badges != null) {
                expect(badges.left - categoryRect.right, closeTo(4, 0.1));
                expect(badges.left, greaterThanOrEqualTo(categoryRect.right));
                expect(badges.right, lessThanOrEqualTo(originalRect.left));
                if (flags.$1 && flags.$2) {
                  final adsRect =
                      bounds(tester, find.byType(EHGalleryAdsBadge));
                  final aiRect = bounds(tester, find.byType(EHGalleryAiBadge));
                  // Fitting may shrink both badges and their shared 4px gap.
                  expect(
                      aiRect.left - adsRect.right, inInclusiveRange(0.0, 4.1));
                }
              }
              expect(tester.takeException(), isNull);
            }
            // Both settings remain independently reactive when both tags exist.
            styleSetting.showAdsBadge.value = false;
            await tester.pump();
            expect(find.byType(EHGalleryAdsBadge), findsNothing);
            expect(find.byType(EHGalleryAiBadge), findsOneWidget);
            expect(
                bounds(tester, find.byType(EHGalleryAiBadge)).left -
                    bounds(tester, find.byType(EHGalleryCategoryTag)).right,
                closeTo(4, 0.1));
            styleSetting.showAiBadge.value = false;
            await tester.pump();
            expect(find.byType(EHGalleryAiBadge), findsNothing);
            expect(bounds(tester, find.byType(EHGalleryCategoryTag)),
                categoryAnchor);
            expect(bounds(tester, find.byKey(const ValueKey('original'))),
                originalAnchor);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }
}
