import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Presentation only: the parser and scheduler remain the source of truth.
class DownloadSearchRulesHint extends StatelessWidget {
  const DownloadSearchRulesHint({super.key, required this.regexMode});

  final bool regexMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('downloadSearchRules'.tr,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                (regexMode
                        ? 'downloadSearchRegexHint'
                        : 'downloadSearchLiteralHint')
                    .tr,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (regexMode)
                _rule(context, 'regexSearch'.tr, r'(?=.*A)(?=.*B)',
                    'downloadSearchRegexExample')
              else ...[
                _rule(context, 'AND', '+tomboy +stocking',
                    'downloadSearchAndHint'),
                _rule(context, 'OR', 'tomboy|stocking', 'downloadSearchOrHint'),
                _rule(context, 'NOT', 'tomboy -pantyhose',
                    'downloadSearchNotHint'),
                _rule(context, 'downloadSearchCombined'.tr, '+A +B|C -D',
                    'downloadSearchCombinedHint'),
              ],
              _rule(context, 'downloadSearchCase'.tr, 'Aa → aa',
                  'downloadSearchCaseHint'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rule(BuildContext context, String label, String syntax,
      String descriptionKey) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              Text(syntax,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.primary)),
            ],
          ),
          const SizedBox(height: 3),
          Text(descriptionKey.tr,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
