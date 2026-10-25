import 'package:flutter/material.dart';

/// Hide the cover's overlays with its native Hero placeholder, but fly only
/// the image. No navigation listeners, timers or retained page state are needed.
class EHCoverHero extends StatelessWidget {
  final Object? tag;
  final Widget cover;
  final List<Widget> overlays;

  const EHCoverHero({
    super.key,
    required this.tag,
    required this.cover,
    required this.overlays,
  });

  @override
  Widget build(BuildContext context) {
    final content = _CoverHeroContent(cover: cover, overlays: overlays);
    if (tag == null) {
      return content;
    }
    return Hero(
      tag: tag!,
      placeholderBuilder: (_, size, __) => SizedBox.fromSize(size: size),
      flightShuttleBuilder: (_, __, ___, from, to) {
        final target = (to.widget as Hero).child;
        final image = target is _CoverHeroContent ? target.cover : target;
        // Use the destination's measured bounds, not an unbounded LayoutBuilder
        // in the flight overlay. Badges never enter this subtree on push or pop.
        final targetBox = to.findRenderObject()! as RenderBox;
        return FittedBox(
          fit: BoxFit.fill,
          child: SizedBox.fromSize(size: targetBox.size, child: image),
        );
      },
      child: content,
    );
  }
}

class _CoverHeroContent extends StatelessWidget {
  final Widget cover;
  final List<Widget> overlays;

  const _CoverHeroContent({required this.cover, required this.overlays});

  @override
  Widget build(BuildContext context) => Stack(children: [cover, ...overlays]);
}
