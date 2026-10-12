import 'dart:async';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

import '../database/database.dart';
import '../utils/tag_rich_label_parser.dart';

typedef TagIconBuilder = Widget Function(
    TagLabelImage image, double size, Widget fallback);

/// Inline decoration only: gestures remain owned by the surrounding tag/card.
class EHTagLabel extends StatelessWidget {
  final TagData tagData;
  final TextStyle style;
  final bool showRichContent;
  final double maxIconSize;
  final String suffix;
  final TagIconBuilder? imageBuilder;

  const EHTagLabel({
    super.key,
    required this.tagData,
    required this.style,
    this.showRichContent = false,
    this.maxIconSize = 16,
    this.suffix = '',
    this.imageBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final String plain = tagData.tagName ?? tagData.key;
    final List<TagLabelToken> tokens = showRichContent
        ? TagRichLabelParser.parse(tagData.fullTagName)
        : const [];
    if (tokens.isEmpty) {
      return Text(plain + suffix,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    final bool hasText = tokens
        .whereType<TagLabelText>()
        .any((token) => token.text.trim().isNotEmpty);
    final double size = maxIconSize.clamp(8.0, 16.0);
    final List<InlineSpan> spans = [];
    for (final TagLabelToken token in tokens) {
      if (token is TagLabelText) {
        spans.add(TextSpan(text: token.text));
      } else if (token is TagLabelImage) {
        // Most names already contain text; avoid duplicated alt text on failure.
        final Widget fallback = hasText
            ? const SizedBox.shrink()
            : Text(token.alt.isNotEmpty ? token.alt : plain, style: style);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: ExcludeSemantics(
            child: imageBuilder?.call(token, size, fallback) ??
                _TagIcon(url: token.url, size: size, fallback: fallback),
          ),
        ));
      }
    }
    spans.add(TextSpan(text: suffix));
    return Text.rich(
      TextSpan(children: spans),
      semanticsLabel: plain + suffix,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _TagIcon extends StatefulWidget {
  final String url;
  final double size;
  final Widget fallback;
  const _TagIcon(
      {required this.url, required this.size, required this.fallback});

  @override
  State<_TagIcon> createState() => _TagIconState();
}

class _TagIconState extends State<_TagIcon> {
  Timer? _deadline;
  bool _timedOut = false;

  void _startDeadline() {
    _deadline?.cancel();
    _timedOut = false;
    // Hide slow loading decoration, not the provider itself: a late successful
    // response must still be allowed to replace this fallback.
    _deadline = Timer(const Duration(seconds: 15), () {
      if (mounted) {
        setState(() => _timedOut = true);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _startDeadline();
  }

  @override
  void didUpdateWidget(covariant _TagIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _startDeadline();
    }
  }

  @override
  void dispose() {
    _deadline?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExtendedImage.network(
      widget.url,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      cache: true,
      cacheMaxAge: const Duration(days: 30),
      printError: false,
      cacheWidth: 64,
      cacheHeight: 64,
      retries: 0,
      timeLimit: const Duration(seconds: 15),
      headers: const {},
      loadStateChanged: (state) {
        if (state.extendedImageLoadState != LoadState.loading) {
          _deadline?.cancel();
        }
        return switch (state.extendedImageLoadState) {
          LoadState.loading => _timedOut
              ? widget.fallback
              : SizedBox(width: widget.size, height: widget.size),
          LoadState.failed => widget.fallback,
          LoadState.completed => null,
        };
      },
    );
  }
}
