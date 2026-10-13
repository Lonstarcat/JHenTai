# Android notification fixes and list reorder diagnosis

Date: 2026-10-14. Branch: `feature/enhanced`; base: `a098f245`.

## Notification changes

- Custom notification text now uses notification-only `values` / `values-night`
  colors. The system owns the notification background; Flutter theme settings
  no longer determine these text colors. The unused compact layout shares the
  same colors, without enabling a second/custom compact progress bar.
- Dart sends `showProgress = ongoing && primary != null`. Kotlin explicitly
  applies `VISIBLE` / `GONE`; a terminal update also forces the bar off even if
  an older sender omits this field. Unknown totals still show indeterminate
  progress while a task is active. Paused tasks retain their progress.
- Existing completion lifetime (8 seconds), channels, permissions, pause/resume,
  notification routing and in-app bottom-position overlay are unchanged.

## List reorder diagnosis — no sorting code changes

The production path is an outer `ReorderableListView.builder` of groups in
`gallery_list_download_page.dart`, with each expanded group containing
`DownloadReorderItemList` in `download_reorder_widgets.dart`. The inner list uses
`shrinkWrap: true`, is non-scrollable and receives unbounded vertical constraints
from the group's `Column`. It measures the entire group's height rather than a
bounded screen viewport. Archive list mode shares this component.

### Controlled layout probe

A temporary Flutter widget test used the actual production group/list component
with 200 synthetic 140px rows. No manga files, images, network or database were
used. On the default 800×600 logical test viewport:

| Layout | Unique rows built on initial layout |
| --- | ---: |
| Production nested expanded group | 200 / 200 |
| Bounded standalone reorderable list (control) | 7 / 200 |

This confirms the loss of viewport-level lazy construction. It is **not** a
device FPS benchmark and does not quantify UI/raster frame times.

### Cost by phase

| Phase | Evidence / cost |
| --- | --- |
| Enter/expand group | Full group is mounted. Real rows additionally contain covers (`EHImage`), multiple `GetBuilder`s and full download-card layout. `AbsorbPointer` disables input, not rendering work. |
| Drag/move | Flutter SDK `SliverReorderableListState._dragUpdateItems` examines mounted row geometry to select an insertion index, then updates gap animations across mounted rows when it changes. Mounting all 200 amplifies this work. |
| Drop/rebuild | `reorderGalleriesInGroup` sorts a copy of the entire library, then filters the group, for each group builder invocation; `saveGalleryOrderAfterReordered` rewrites every group row's `sortOrder` and refreshes the body. This is not executed for every pointer move. |
| Drop/persist | `GalleryDownloadService.updateGalleryOrder` updates all group rows in one DB transaction, then marks all metadata dirty. Existing per-gallery 500ms metadata timers can later serialize/write the group. This can add post-drop work, but does not explain continuous drag jank alone. |

Primary structural suspect: nested shrink-wrapping + all rows mounted. Full card
complexity amplifies it. Pointer boundary `findRenderObject` / `localToGlobal`
checks add per-event work but are not proportional to the number of rows.

The initial diagnosis did not change sorting code. The subsequent implementation
below was separately authorized by the user. Confirming the precise contribution
on the user's device still requires a profile-mode frame trace; no FPS claim is made.

## Authorized reorder implementation

- Both gallery and archive list pages now use `DownloadReorderView`: a single
  `CustomScrollView`, interleaved group headers and independent per-group
  `SliverReorderableList`s. Production rows keep their full card and 140px extent;
  mobile long-press and desktop immediate drag are unchanged.
- Group-handle down registers the original pointer with a small public-API
  `MultiDragGestureRecognizer` before collapsing. Acceptance is gated until the
  header-only sliver is laid out. Early up/cancel cannot start a stale drag. The
  original expansion/scroll position is restored after proxy removal.
- Group boundaries use logical content offsets, fixed row extents and the shared
  viewport/scroll offset, not an enormous full-group RenderBox. Drops outside the
  owning group do not commit; each sliver only owns local item indices.
- Each page rebuild sorts the library once and buckets it by group, rather than
  sorting once per header. The view retains a drag snapshot; membership changes
  cancel a stale drag. Old proxy cleanup cannot clear a newer gesture.
- Canonical integer orders are assigned on drop; only actual changes are saved.
  Legacy duplicate/sparse orders and title/date order may need a full-group first
  normalization. Already canonical groups write only the affected range.
- Immutable gid/order values are captured at enqueue time. Service-owned writers
  serialize saves, continue after failure and merge failed subsets into the next
  save. Archive order writes update only `sortOrder`, not download status/group.
  Existing metadata persistence is reused only for changed entries; DB schema,
  download queue and metadata format are unchanged. Save failures show the
  existing localized `saveFailed` error notification, without rolling back later
  in-memory moves.
- Focused synthetic sliver probes with 200/500 rows build 16 initial 50px test
  rows (<20), rather than 200/500. These use deliberately shorter synthetic rows
  to stress the viewport, not a measured real-device frame rate. Existing reorder
  behavior tests and writer snapshot/serialization/failure cases are retained.

## Focused verification and manual checks

- Synthetic layout probe: passed (200 vs 7), temporary test outside the repo.
- Android resource XML parsing, Dart analyzer and Android arm64 Release build
  validate resources, payload typing and Kotlin compilation; they do not prove
  the final appearance on every manufacturer's notification panel.
- User checks: system light/dark (including a different app theme); active,
  paused and unknown-total tasks; terminal completion with no progress bar;
  a new task after completion must restore progress; existing pause/resume and
  notification navigation must continue to work.
- No commit, push, Actions or real-library operation. The final local packages
  include both these authorized reorder changes and the prior notification fixes.
