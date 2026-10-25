import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/ui_config.dart';
import '../setting/style_setting.dart';
import 'eh_gallery_category_tag.dart';

/// Outline styling matches the existing original-image badges.
class EHGalleryAdsBadge extends StatelessWidget {
  final bool onCover;
  final bool useThemePrimary;

  const EHGalleryAdsBadge.inline({super.key, this.useThemePrimary = false})
      : onCover = false;
  const EHGalleryAdsBadge.cover({super.key, this.useThemePrimary = false})
      : onCover = true;

  @override
  Widget build(BuildContext context) => _GalleryTagBadge(
        label: 'galleryAdsBadge'.tr,
        onCover: onCover,
        useThemePrimary: useThemePrimary,
      );
}

/// The raw AI-generated tag is unrelated to the download super-resolution state.
class EHGalleryAiBadge extends StatelessWidget {
  final bool onCover;
  final bool useThemePrimary;

  const EHGalleryAiBadge.inline({super.key, this.useThemePrimary = false})
      : onCover = false;
  const EHGalleryAiBadge.cover({super.key, this.useThemePrimary = false})
      : onCover = true;

  @override
  Widget build(BuildContext context) => _GalleryTagBadge(
        label: 'galleryAiBadge'.tr,
        onCover: onCover,
        useThemePrimary: useThemePrimary,
      );
}

class _GalleryTagBadge extends StatelessWidget {
  final String label;
  final bool onCover;
  final bool useThemePrimary;

  const _GalleryTagBadge({
    required this.label,
    required this.onCover,
    required this.useThemePrimary,
  });

  @override
  Widget build(BuildContext context) {
    final color = useThemePrimary
        ? Theme.of(context).colorScheme.primary
        : onCover
            ? UIConfig.onBackGroundColor(context)
            : UIConfig.resumePauseButtonColor(context);
    return IgnorePointer(
      child: Container(
        // Flutter rounds the category's 15px line box up to logical pixels.
        // Add its existing 3/4px padding, without expensive intrinsic layout.
        height: onCover
            ? null
            : MediaQuery.textScalerOf(context).scale(15).ceilToDouble() + 7,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        alignment: onCover ? null : Alignment.center,
        decoration: BoxDecoration(
          color: onCover ? UIConfig.backGroundColor(context) : null,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: color,
            fontWeight: onCover ? null : FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Keep category and optional badge together without intrinsic layout passes.
class EHGalleryCategoryWithAds extends StatelessWidget {
  final String category;
  final bool hasAds;
  final bool hasAi;
  final bool useThemePrimary;

  const EHGalleryCategoryWithAds({
    super.key,
    required this.category,
    required this.hasAds,
    this.hasAi = false,
    this.useThemePrimary = false,
  });

  @override
  Widget build(BuildContext context) => Obx(() {
        final bool showAds = styleSetting.showAdsBadge.value;
        final bool showAi = styleSetting.showAiBadge.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EHGalleryCategoryTag(category: category),
            if (hasAds && showAds) ...[
              const SizedBox(width: 4),
              EHGalleryAdsBadge.inline(useThemePrimary: useThemePrimary),
            ],
            if (hasAi && showAi) ...[
              const SizedBox(width: 4),
              EHGalleryAiBadge.inline(useThemePrimary: useThemePrimary),
            ],
          ],
        );
      });
}

/// Download lists keep the category and right-hand controls at their existing
/// anchors. Only the optional badge group uses the flexible space between them.
class EHDownloadCategoryWithBadges extends StatelessWidget {
  final String category;
  final bool hasAds;
  final bool hasAi;
  final double trailingInset;

  const EHDownloadCategoryWithBadges({
    super.key,
    required this.category,
    required this.hasAds,
    required this.hasAi,
    this.trailingInset = 0,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
        EHGalleryCategoryTag(category: category),
        Expanded(
          child: Obx(() {
            final showAds = styleSetting.showAdsBadge.value;
            final showAi = styleSetting.showAiBadge.value;
            final ads = hasAds && showAds;
            final ai = hasAi && showAi;
            if (!ads && !ai) {
              return const SizedBox.shrink();
            }
            return Padding(
              // Account for the original badge's existing leading margin;
              // no category/original margin or trailing control is changed.
              padding: EdgeInsets.only(left: trailingInset),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (ads) const EHGalleryAdsBadge.inline(),
                    if (ads && ai) const SizedBox(width: 4),
                    if (ai) const EHGalleryAiBadge.inline(),
                  ]),
                ),
              ),
            );
          }),
        ),
      ]);
}

/// A reactive, bottom-left badge column shared by online and local covers.
/// Hidden badges reserve no space, including the gap to right-hand grid chips.
class EHGalleryCoverBadges extends StatelessWidget {
  final bool hasAds;
  final bool hasAi;
  final bool useThemePrimary;
  final double trailingSpacing;

  const EHGalleryCoverBadges({
    super.key,
    required this.hasAds,
    required this.hasAi,
    this.useThemePrimary = false,
    this.trailingSpacing = 0,
  });

  @override
  Widget build(BuildContext context) => Obx(() {
        final bool showAds = styleSetting.showAdsBadge.value;
        final bool showAi = styleSetting.showAiBadge.value;
        final bool ads = hasAds && showAds;
        final bool ai = hasAi && showAi;
        if (!ads && !ai) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: EdgeInsets.only(right: trailingSpacing),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ads)
                EHGalleryAdsBadge.cover(useThemePrimary: useThemePrimary),
              if (ads && ai) const SizedBox(height: 2),
              if (ai) EHGalleryAiBadge.cover(useThemePrimary: useThemePrimary),
            ],
          ),
        );
      });
}
