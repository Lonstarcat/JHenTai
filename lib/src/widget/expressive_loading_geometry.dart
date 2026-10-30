import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/physics.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

/// Material/AndroidX polygons, not sampled circles or unrelated SVG silhouettes.
/// Motion reference: AndroidX Material3 LoadingIndicator.kt (Apache-2.0).
/// See docs/expressive-loading-indicator.md for provenance and design choices.
abstract final class ExpressiveLoadingGeometry {
  static const int morphIntervalMicroseconds = 650000;
  static const int globalRotationMicroseconds = 4666000;
  static const double activeSizeRatio = 38 / 48;

  static final List<RoundedPolygon> shapes = List.unmodifiable([
    MaterialShapes.softBurst,
    MaterialShapes.cookie9Sided,
    MaterialShapes.pentagon,
    MaterialShapes.pill,
    MaterialShapes.sunny,
    MaterialShapes.cookie4Sided,
    MaterialShapes.oval,
  ]);

  // Curve matching is the expensive part: compute just seven Morphs once and
  // share them across all loaders. Each painter still owns its mutable Path.
  static final List<Morph> _morphs = List.generate(
    shapes.length,
    (index) => Morph(shapes[index], shapes[(index + 1) % shapes.length]),
    growable: false,
  );

  static final SpringSimulation _spring = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 200, ratio: 0.6),
    0,
    1,
    0,
    tolerance: const Tolerance(distance: 0.1, velocity: 0.1),
    snapToEnd: true,
  );

  static final double _rotationSafeDiameter =
      shapes.fold<double>(0, (diameter, shape) {
    final bounds = shape.calculateMaxBounds();
    return math.max(
        diameter, math.max(bounds[2] - bounds[0], bounds[3] - bounds[1]));
  });

  static ({int index, double progress, double rotation}) frame(
      Duration elapsed) {
    final micros = math.max(0, elapsed.inMicroseconds);
    final transition = micros ~/ morphIntervalMicroseconds;
    final seconds =
        (micros % morphIntervalMicroseconds) / Duration.microsecondsPerSecond;
    final spring = _spring.x(seconds);
    return (
      index: transition % shapes.length,
      // Extrapolating Bezier control points during spring overshoot can create
      // spikes. Keep contours bounded; preserve spring overshoot in rotation.
      progress: spring.clamp(0.0, 1.0),
      rotation: ((transition % 4 + 1 + spring) * math.pi / 2 +
              (micros % globalRotationMicroseconds) /
                  globalRotationMicroseconds *
                  2 *
                  math.pi) %
          (2 * math.pi),
    );
  }

  static Path path(Duration elapsed, {Path? reuse}) {
    final current = frame(elapsed);
    return _morphs[current.index]
        .toPath(progress: current.progress, path: reuse);
  }

  static Offset center(Duration elapsed) {
    final current = frame(elapsed);
    final start = shapes[current.index];
    final end = shapes[(current.index + 1) % shapes.length];
    return Offset.lerp(Offset(start.centerX, start.centerY),
        Offset(end.centerX, end.centerY), current.progress)!;
  }

  static void paint(Canvas canvas, Size size, Duration elapsed, Color color,
      {Path? reuse}) {
    if (size.isEmpty) {
      return;
    }
    final contour = path(elapsed, reuse: reuse);
    // Path.getBounds uses Bezier control hulls. Morph feature matching splits
    // curves differently on either side of a seam: identical filled contours
    // can report different bounds. Stable polygon centers prevent tiny jumps.
    final pivot = center(elapsed);
    final scale = size.shortestSide * activeSizeRatio / _rotationSafeDiameter;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(frame(elapsed).rotation);
    canvas.scale(scale);
    canvas.translate(-pivot.dx, -pivot.dy);
    canvas.drawPath(
        contour,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill
          ..isAntiAlias = true);
    canvas.restore();
  }
}
