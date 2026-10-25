/// Stable names are persisted in StyleSetting JSON. Never rename existing IDs.
enum DownloadToolbarKind { gallery, archive }

enum DownloadToolbarAction {
  selectAll,
  resume,
  pause,
  batchUpdate,
  favorite,
  changeGroup,
  delete,
  changeParseSource;

  bool get requiresSelection => this != selectAll;

  String get labelKey => switch (this) {
        selectAll => 'toolbarSelectAll',
        resume => 'resume',
        pause => 'pause',
        batchUpdate => 'batchUpdate',
        favorite => 'batchFavorite',
        changeGroup => 'changeGroup',
        delete => 'delete',
        changeParseSource => 'toolbarChangeParseSource',
      };
}

/// Immutable order includes hidden actions, so toggling never loses position.
class DownloadToolbarConfig {
  final List<DownloadToolbarAction> order;
  final Set<DownloadToolbarAction> enabled;

  DownloadToolbarConfig._(Iterable<DownloadToolbarAction> order,
      Iterable<DownloadToolbarAction> enabled)
      : order = List.unmodifiable(order),
        enabled = Set.unmodifiable(enabled);

  static List<DownloadToolbarAction> supported(DownloadToolbarKind kind) =>
      DownloadToolbarAction.values
          .where((action) =>
              kind == DownloadToolbarKind.archive ||
              action != DownloadToolbarAction.changeParseSource)
          .toList();

  factory DownloadToolbarConfig.defaults(DownloadToolbarKind kind) {
    final actions = supported(kind);
    return DownloadToolbarConfig._(actions, actions);
  }

  factory DownloadToolbarConfig.fromJson(
      Object? raw, DownloadToolbarKind kind) {
    if (raw is! Map) {
      return DownloadToolbarConfig.defaults(kind);
    }
    final defaults = supported(kind);
    List<DownloadToolbarAction> parse(Object? value) {
      if (value is! List) {
        return List.of(defaults);
      }
      final result = <DownloadToolbarAction>[];
      for (final id in value) {
        for (final action in defaults) {
          if (id == action.name && !result.contains(action)) {
            result.add(action);
          }
        }
      }
      return result;
    }

    final order = parse(raw['order']);
    final missing =
        defaults.where((action) => !order.contains(action)).toList();
    final enabled = parse(raw['enabled']);
    // IDs absent from the old order are new (or damaged): append default-enabled.
    // Explicitly disabled IDs in an existing order remain disabled, including all-off.
    order.addAll(missing);
    enabled.addAll(missing);
    return DownloadToolbarConfig._(order, enabled);
  }

  Iterable<DownloadToolbarAction> get visible => order.where(enabled.contains);

  DownloadToolbarConfig toggle(DownloadToolbarAction action, bool value) =>
      DownloadToolbarConfig._(
        order,
        value
            ? {...enabled, if (order.contains(action)) action}
            : enabled.where((item) => item != action),
      );

  /// Flutter's onReorderItem already normalizes the destination after removal.
  DownloadToolbarConfig reorder(int oldIndex, int newIndex) {
    final next = List.of(order);
    next.insert(newIndex, next.removeAt(oldIndex));
    return DownloadToolbarConfig._(next, enabled);
  }

  Map<String, Object> toJson() => {
        'order': order.map((action) => action.name).toList(),
        'enabled':
            order.where(enabled.contains).map((action) => action.name).toList(),
      };
}
