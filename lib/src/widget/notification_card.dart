import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../model/notification_entry.dart';
import '../service/notification_manager.dart';

class NotificationCard extends StatefulWidget {
  final NotificationEntry entry;
  final NotificationManager manager;
  const NotificationCard({super.key, required this.entry, required this.manager});
  @override
  State<NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<NotificationCard> with TickerProviderStateMixin {
  late final AnimationController _appearance =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450), reverseDuration: NotificationManager.exitDuration)
        ..forward();
  late final AnimationController _drag = AnimationController.unbounded(vsync: this);
  double _width = 0;
  @override
  void didUpdateWidget(covariant NotificationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.exiting != widget.entry.exiting) {
      if (widget.entry.exiting) {
        _appearance.animateBack(0, duration: NotificationManager.exitDuration);
      } else {
        _drag.value = 0;
        _appearance.forward();
      }
    }
  }

  @override
  void dispose() {
    _appearance.dispose();
    _drag.dispose();
    super.dispose();
  }

  void _startDrag(DragStartDetails details) {
    if (widget.entry.exiting) {
      return;
    }
    _width = context.size?.width ?? 0;
    _drag.stop();
    widget.manager.setDragging(widget.entry.id, true);
  }

  void _endDrag(double velocity) {
    if (widget.entry.exiting) {
      return;
    }
    if (_width > 0 && (_drag.value.abs() >= _width * .35 || (velocity.abs() > 700 && velocity.sign == _drag.value.sign))) {
      final direction = _drag.value == 0 ? velocity.sign : _drag.value.sign;
      _drag.animateTo(direction * math.max(_width, _drag.value.abs()), duration: NotificationManager.exitDuration, curve: Curves.easeOut);
      widget.manager.dismiss(widget.entry.id);
    } else {
      _drag.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      widget.manager.setDragging(widget.entry.id, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = switch (widget.entry.level) {
      NotificationLevel.info => colors.primary,
      NotificationLevel.success => dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
      NotificationLevel.warning => dark ? const Color(0xFFFFD54F) : const Color(0xFF8D6300),
      NotificationLevel.error => colors.error,
    };
    final icon = switch (widget.entry.level) {
      NotificationLevel.info => Icons.info_outline_rounded,
      NotificationLevel.success => Icons.check_circle_outline_rounded,
      NotificationLevel.warning => Icons.warning_amber_rounded,
      NotificationLevel.error => Icons.error_outline_rounded,
    };
    final card = GestureDetector(
      onHorizontalDragStart: _startDrag,
      onHorizontalDragUpdate: (details) {
        if (!widget.entry.exiting) {
          _drag.value += details.primaryDelta ?? 0;
        }
      },
      onHorizontalDragEnd: (details) => _endDrag(details.primaryVelocity ?? 0),
      onHorizontalDragCancel: () => _endDrag(0),
      child: Material(
        color: Color.alphaBlend(accent.withValues(alpha: dark ? .10 : .05), colors.surfaceContainerHigh),
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: colors.shadow.withValues(alpha: .25),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.entry.action == null ? null : () => widget.manager.invokeAction(widget.entry.id),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52, maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.only(left: 14, right: 4, top: 8, bottom: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: accent, size: 22),
                const SizedBox(width: 12),
                Flexible(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (widget.entry.title?.isNotEmpty ?? false)
                    Text(widget.entry.title!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: colors.onSurface)),
                  if (widget.entry.message.isNotEmpty)
                    Text(widget.entry.message,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurface)),
                ])),
                if (widget.entry.count > 1)
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text('×${widget.entry.count}', style: TextStyle(color: accent))),
                // This root Stack is outside Navigator's Overlay. Accessible
                // labels instead of Tooltips avoid requiring a page Overlay.
                if (widget.entry.action != null)
                  Semantics(
                      label: widget.entry.actionLabel ?? MaterialLocalizations.of(context).continueButtonLabel,
                      button: true,
                      child: IconButton(
                          icon: Icon(Icons.arrow_forward_rounded, color: accent, size: 20),
                          onPressed: () => widget.manager.invokeAction(widget.entry.id))),
                Semantics(
                    label: MaterialLocalizations.of(context).closeButtonTooltip,
                    button: true,
                    child: IconButton(
                        icon: Icon(Icons.close_rounded, color: colors.onSurfaceVariant, size: 18),
                        onPressed: () => widget.manager.dismiss(widget.entry.id))),
              ]),
            ),
          ),
        ),
      ),
    );
    return Semantics(
        liveRegion: true,
        child: AnimatedBuilder(
          animation: Listenable.merge([_appearance, _drag]),
          child: card,
          builder: (context, child) {
            final value = Curves.easeOutCubic.transform(_appearance.value);
            final dragOpacity = _width > 0 ? 1 - (_drag.value.abs() / _width).clamp(0.0, 1.0) : 1.0;
            return IgnorePointer(
                ignoring: widget.entry.exiting,
                child: Align(
                  alignment: Alignment.bottomRight,
                  widthFactor: 1,
                  heightFactor: value,
                  child: Opacity(
                      opacity: value * dragOpacity,
                      child: Transform.translate(
                        offset: Offset(_drag.value, 16 * (1 - value)),
                        child: Transform.scale(
                            scale: .94 + .06 * value,
                            alignment: Alignment.bottomRight,
                            child: Padding(padding: const EdgeInsets.only(bottom: 8), child: child)),
                      )),
                ));
          },
        ));
  }
}
