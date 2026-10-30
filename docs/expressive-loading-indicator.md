# Expressive loading indicator (first integration)

`ExpressiveLoadingIndicator` supports `size`, `color`, `running`, `visible`,
`reducedMotion` and `semanticsLabel`. Typical sizes are 24, 32 and 48 logical
pixels; the existing 16/18/20px compact slots keep their original footprint.
The default color is the active theme's `colorScheme.primary`.

## Geometry and motion

- Seven Material polygons in order: Soft Burst → Cookie 9 → Pentagon → Pill →
  Sunny → Cookie 4 → Oval → Soft Burst.
- `material_new_shapes` 1.0.0 provides the AndroidX rounded-polygon / cubic Bezier
  feature-matching Morph implementation, not approximate radial shapes.
- Morph pairs are cached once; each painter reuses its own mutable Path.
  Drawing pivots interpolate stable polygon centers, not per-frame cubic
  control-hull bounds (which change when Morph splits curve segments).
- AndroidX motion reference: 650ms between morphs, spring damping 0.6,
  stiffness 200, quarter-turn morph rotation and a 4666ms global rotation.
  Contour interpolation is clamped to avoid overshoot spikes while rotation
  retains the spring's rebound. The closing Oval → Soft Burst pair is explicit.
- A single Flutter Ticker updates only a CustomPainter via ChangeNotifier.
  There are no periodic timers, AnimatedBuilder page rebuilds or raster assets.
- `running: false` freezes the current frame; `visible: false` paints nothing
  while preserving layout size. TickerMode and app lifecycle stop the clock.
  Mobile V2 and desktop retained Offstage tab/drawer pages now provide matching
  TickerMode flags, so invisible pages do not keep these loaders ticking.
- A visible but temporarily unfocused app (`inactive`, notably on Android)
  continues animating. Only `hidden`, `paused` and `detached` lifecycle states
  stop the clock; classifying `inactive` as background previously froze a new
  details placeholder at its initial shape. This policy is shared by all callers.
- System reduce-motion defaults to a static filled
  shape (still communicates loading via the caller's optional semantic label).
  Set `reducedMotion` explicitly to override that default.
- Assistive navigation (`accessibleNavigation`, e.g. TalkBack) is independent of
  `disableAnimations` and must not stop the loader by itself. The previous OR
  check incorrectly froze the initial shape with reduce-motion off. An offline
  Pixel 10 Android 17 release/Impeller probe reproduces this flag combination;
  it does not establish which flags the user's physical device reports.

## Integration boundary

Replaced the shared `UIConfig.loadingAnimation` (default LoadingStateIndicator,
page/local/dialog loaders), download-grid pending-cover dots, and tag dialog
follow/hide/vote waiting icons on mobile and desktop. Loading state transitions,
callbacks, errors and layout sizes are unchanged. Existing explicit Cupertino
variants and deterministic image/download/archive/read progress bars remain.
The earlier uncommitted download-page locator fix is preserved.

## Dependency evaluation and attribution

The suggested `material3_expressive_loading_indicator` 0.1.2 was inspected: MIT
with AOSP attribution, Flutter-only plus `material_new_shapes`, last published
2026-05-09. Its periodic morph timer and size-dependent scaling were not adopted.
Only the smaller shape primitive package was added, pinned to 1.0.0. It supports
Flutter >=3.22 / Dart >=3.6 and all Flutter platforms; meta/vector_math already
exist in this project's SDK dependency graph. No native plugin/UI framework.
The shape package is MIT, copyright 2025 Agbama Gifted, and is based on
`androidx.graphics.shapes`. Its bundled LICENSE is included by Flutter's normal
dependency-license collection. This component's clock/lifecycle/renderer are
implemented locally, with motion parameters informed by the Apache-2.0 AndroidX
reference. No code was copied from FlClash or the suggested indicator package.
Current FlClash CommonCircleLoading is a comet ring, intentionally not reused.

Sources:
- https://m3.material.io/components/loading-indicator/overview
- https://github.com/androidx/androidx/blob/androidx-main/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/LoadingIndicator.kt
- https://pub.dev/packages/material_new_shapes/versions/1.0.0
- https://pub.dev/packages/material3_expressive_loading_indicator/versions/0.1.2
- https://github.com/chen08209/FlClash/blob/main/lib/ui/loading.dart

This is a Flutter implementation following the reference, not an official Google
Flutter widget or a claim of pixel-identical behavior. Device-level visual and
performance acceptance remains part of manual testing.
