import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Jumps a lazy list/grid near the requested task and then asks Flutter to
/// reveal the real widget. This is only called from a fully mounted download
/// page, so it does not depend on notification/page-transition timing.
Future<bool> revealDownloadTask({
  required ScrollController controller,
  required GlobalKey itemKey,
  required double estimatedOffset,
}) async {
  await WidgetsBinding.instance.endOfFrame;
  if (!controller.hasClients) {
    return false;
  }

  final ScrollPosition position = controller.position;
  controller.jumpTo(
    estimatedOffset
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble(),
  );

  BuildContext? targetContext;
  for (int attempt = 0; attempt < 3 && targetContext == null; attempt++) {
    await WidgetsBinding.instance.endOfFrame;
    targetContext = itemKey.currentContext;
    if (targetContext == null) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
  if (targetContext == null) {
    return false;
  }

  await Scrollable.ensureVisible(
    targetContext,
    alignment: 0.15,
    duration: const Duration(milliseconds: 350),
    curve: Curves.easeOutCubic,
  );
  return true;
}

double downloadListTaskOffset({
  required List<String> groups,
  required Set<String> expandedGroups,
  required String targetGroup,
  required int targetIndex,
  required int Function(String group) itemCount,
  required double groupExtent,
  required double itemExtent,
}) {
  double offset = 0;
  for (final String group in groups) {
    offset += groupExtent;
    if (group == targetGroup) {
      return offset + targetIndex * itemExtent;
    }
    if (expandedGroups.contains(group)) {
      offset += itemCount(group) * itemExtent;
    }
  }
  return offset;
}

int downloadGridCrossAxisCount({
  required double availableWidth,
  required int? configuredCount,
  required double maxCrossAxisExtent,
  required double crossAxisSpacing,
}) {
  if (configuredCount != null) {
    return math.max(1, configuredCount);
  }
  return math.max(
    1,
    (availableWidth / (maxCrossAxisExtent + crossAxisSpacing)).ceil(),
  );
}

double downloadGridTaskOffset({
  required int itemIndex,
  required int crossAxisCount,
  required double availableWidth,
  required double crossAxisSpacing,
  required double mainAxisSpacing,
  required double childAspectRatio,
}) {
  final double childCrossAxisExtent =
      (availableWidth + crossAxisSpacing) / crossAxisCount - crossAxisSpacing;
  final double childMainAxisExtent = childCrossAxisExtent / childAspectRatio;
  final int row = itemIndex ~/ crossAxisCount;
  return row * (childMainAxisExtent + mainAxisSpacing);
}
