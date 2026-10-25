import 'dart:math' as math;
import 'package:flutter/material.dart';

class BatchUpdateStatistic {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  const BatchUpdateStatistic(this.label, this.value, this.icon, {this.onTap});
}

/// At most three columns, using measured translated labels rather than a
/// character-count heuristic. Narrow screens retain two aligned columns.
class BatchUpdateStatistics extends StatelessWidget {
  final List<BatchUpdateStatistic> items;
  final bool compact;
  const BatchUpdateStatistics(
      {super.key, required this.items, this.compact = false});

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final theme = Theme.of(context);
        final style = theme.textTheme.labelSmall!;
        final scaler = MediaQuery.textScalerOf(context);
        double minWidth = 112;
        for (final item in items) {
          final painter = TextPainter(
              text: TextSpan(text: item.label, style: style),
              textDirection: Directionality.of(context),
              textScaler: scaler)
            ..layout();
          minWidth = math.max(minWidth, painter.width + (compact ? 36 : 48));
          painter.dispose();
        }
        const gap = 8.0;
        final columns = constraints.maxWidth >= minWidth * 3 + gap * 2 ? 3 : 2;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final item in items)
            SizedBox(
                width: width,
                child: Material(
                  color: compact
                      ? theme.colorScheme.surfaceContainerLow
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: item.onTap,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 8 : 10),
                      child: compact
                          ? Row(children: [
                              Expanded(
                                  child: Text('${item.label}: ${item.value}',
                                      style: item.onTap == null
                                          ? style
                                          : style.copyWith(
                                              color: theme.colorScheme.primary),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis)),
                              if (item.onTap != null)
                                Icon(Icons.chevron_right,
                                    size: 16, color: theme.colorScheme.primary),
                            ])
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  SizedBox(
                                      height:
                                          scaler.scale(style.fontSize ?? 11) *
                                              2.6,
                                      child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(item.icon,
                                                size: 14,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant),
                                            const SizedBox(width: 5),
                                            Expanded(
                                                child: Text(item.label,
                                                    style: style,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis)),
                                          ])),
                                  const SizedBox(height: 3),
                                  Text(item.value,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600)),
                                ]),
                    ),
                  ),
                )),
        ]);
      });
}
