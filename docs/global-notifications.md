# Global in-app notifications

This is an independent Flutter implementation of the requested FlClash-style
interaction, not a port of its Riverpod architecture or copied source.
Reference: https://github.com/chen08209/FlClash/blob/main/lib/manager/status_manager.dart

## Integration

- `showNotifier(message, NotificationLevel.success)` works without page context.
  Optional title/action/actionLabel preserve existing actionable messages.
- `NotificationManager` owns an immutable ValueNotifier snapshot, a bounded
  Queue (100 waiting items), deduplication, priority and lifecycle timers.
- The root `NotificationOverlay` wraps the app in a transparent Stack. Desktop
  shows four cards; mobile/tablet and narrow windows show two. SafeArea/keyboard
  constraints and vertical scrolling keep short windows usable.
- `NotificationCard` uses the current ColorScheme, max width 500, min height 52,
  light shadows, close/action buttons and bidirectional horizontal dismissal.
- Entrance: 450ms, opacity 0..1, Y -16..0, scale .94..1. Exit: 300ms fade and
  height collapse. Cards retain their slot until the exit finishes.

## Queue behavior

Info/success expire after 3s, warning after 5s and error after 6s, starting when
displayed rather than while waiting. Identical level/title/message merge with a
count badge and renewed lifetime; latest actions replace old actions. Errors
have FIFO priority in the waiting queue. If full, the oldest lowest-priority
non-error exits before the error takes its slot. Existing errors are not evicted.
Dragging pauses that card's timer. Capacity changes reconcile existing cards.
Timers and animation controllers are cancelled on teardown; disposed managers
ignore late calls. Timer publication is deferred when a nested page is building.

## Compatibility and privacy

`toast()` and `snack()` now delegate to the global system. Legacy isCenter/isShort
flags remain accepted but placement/lifetime follow the new unified rules.
Toast defaults to info; snack defaults to error with explicit info/success on
clipboard detection, EH dawn/HV events and archive-bot check-in. Async results
(login, favorites, saves, cloud settings etc.) explicitly set success/error levels;
batch favorite partial failure uses warning. Existing action taps are once-only.

The overlay remains inside AppManager's secure blur (stable GlobalKey prevents
queue destruction on reparenting). A root navigation observer hides messages on
the lock page, including dialogs above it. Lock/background suppression reasons
are independent; countdowns retain remaining duration until presentation resumes.
Native Android download/archive/favorite notifications and channels are unchanged.
No dependency, database migration, search/API or signing changes are required.

## Verification and manual handoff

Per the user's request, only the new manager/overlay targeted tests and analyzer
are run before local release builds, not a full regression or broad manual QA.
Tests cover durations/capacity/dedup/priority/timer disposal, root build safety,
entry/exit bounds, both swipe directions, light/dark, lock route changes, action
compatibility and taps outside cards.

User checks: login result, favorite/rating result, reader image save, clipboard
gallery link action, multiple failures, short/narrow windows, theme switch and
background/lock/unlock. Android system task notifications should remain unchanged.
