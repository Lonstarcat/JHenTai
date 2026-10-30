import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'expressive_loading_geometry.dart';

/// Filled, seven-shape Material 3 Expressive indeterminate loading indicator.
/// Does not replace progress bars with known completion percentages.
class ExpressiveLoadingIndicator extends StatefulWidget {
  const ExpressiveLoadingIndicator({
    super.key,
    this.size = 32,
    this.color,
    this.running = true,
    this.reducedMotion,
    this.visible = true,
    this.semanticsLabel,
  }) : assert(size > 0 && size < double.infinity);

  final double size;
  final Color? color;
  final bool running;

  /// Null follows the platform's reduce-motion setting, not screen-reader use.
  final bool? reducedMotion;

  /// Hidden indicators reserve their size but paint nothing and stop ticking.
  final bool visible;
  final String? semanticsLabel;

  @override
  State<ExpressiveLoadingIndicator> createState() =>
      _ExpressiveLoadingIndicatorState();
}

class _ExpressiveLoadingIndicatorState extends State<ExpressiveLoadingIndicator>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _clock = _LoadingClock();
  late final Ticker _ticker;
  Duration _resumeFrom = Duration.zero;
  bool _tickerModeEnabled = true;
  bool _reduceMotion = false;
  bool _appVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appVisible = _isVisibleLifecycle(lifecycle);
    _ticker = createTicker((elapsed) => _clock.advance(_resumeFrom + elapsed));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerModeEnabled = TickerMode.valuesOf(context).enabled;
    final media = MediaQuery.maybeOf(context);
    // accessibleNavigation means assistive navigation (e.g. TalkBack), not a
    // request to disable animation. Conflating them freezes every loader even
    // when the system's reduce-motion setting is off.
    _reduceMotion = widget.reducedMotion ?? (media?.disableAnimations ?? false);
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ExpressiveLoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final media = MediaQuery.maybeOf(context);
    _reduceMotion = widget.reducedMotion ?? (media?.disableAnimations ?? false);
    _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appVisible = _isVisibleLifecycle(state);
    _syncTicker();
  }

  // Inactive is still visible (e.g. Android temporarily loses window focus,
  // notification shade, split screen). Treating it as background can leave a
  // newly mounted details loader frozen on its first shape until focus returns.
  // TickerMode still independently pauses covered routes and hidden tabs.
  static bool _isVisibleLifecycle(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  void _syncTicker() {
    final animate = widget.visible &&
        widget.running &&
        !_reduceMotion &&
        _tickerModeEnabled &&
        _appVisible;
    if (animate && !_ticker.isActive) {
      _ticker.start();
    } else if (!animate && _ticker.isActive) {
      _resumeFrom = _clock.elapsed;
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: widget.visible
          ? Semantics(
              label: widget.semanticsLabel,
              role: SemanticsRole.loadingSpinner,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _ExpressiveLoadingPainter(_clock,
                      widget.color ?? Theme.of(context).colorScheme.primary),
                ),
              ),
            )
          : null,
    );
  }
}

class _LoadingClock extends ChangeNotifier {
  Duration elapsed = Duration.zero;
  void advance(Duration value) {
    elapsed = value;
    notifyListeners();
  }
}

class _ExpressiveLoadingPainter extends CustomPainter {
  _ExpressiveLoadingPainter(this.clock, this.color) : super(repaint: clock);
  final _LoadingClock clock;
  final Color color;
  final Path _path = Path();

  @override
  void paint(Canvas canvas, Size size) =>
      ExpressiveLoadingGeometry.paint(canvas, size, clock.elapsed, color,
          reuse: _path);

  @override
  bool shouldRepaint(covariant _ExpressiveLoadingPainter oldDelegate) =>
      oldDelegate.clock != clock || oldDelegate.color != color;
}
