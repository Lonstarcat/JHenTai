/// Persist stable names, never enum indices.
enum DownloadPageAction {
  batchUpdateTask,
  switchView,
  multiSelect,
  resumeAll,
  pauseAll,
  reorder,
  search;

  String get labelKey => switch (this) {
        batchUpdateTask => 'batchUpdateTask',
        switchView => 'downloadPageSwitchView',
        multiSelect => 'multiSelect',
        resumeAll => 'resumeAllTasks',
        pauseAll => 'pauseAllTasks',
        reorder => 'downloadPageReorder',
        search => 'search',
      };
}

class DownloadPageActionsConfig {
  final List<DownloadPageAction> order;
  final Set<DownloadPageAction> enabled;
  final DownloadPageAction? externalAction;

  DownloadPageActionsConfig._(Iterable<DownloadPageAction> order,
      Iterable<DownloadPageAction> enabled, this.externalAction)
      : order = List.unmodifiable(order),
        enabled = Set.unmodifiable(enabled);

  factory DownloadPageActionsConfig.defaults() => DownloadPageActionsConfig._(
      DownloadPageAction.values,
      DownloadPageAction.values,
      DownloadPageAction.search);

  factory DownloadPageActionsConfig.fromJson(Object? raw) {
    if (raw is! Map) {
      return DownloadPageActionsConfig.defaults();
    }
    DownloadPageAction? parse(Object? id) {
      for (final action in DownloadPageAction.values) {
        if (id == action.name) {
          return action;
        }
      }
      return null;
    }

    List<DownloadPageAction> parseList(Object? ids) => ids is List
        ? ids.map(parse).whereType<DownloadPageAction>().toSet().toList()
        : List.of(DownloadPageAction.values);
    final order = parseList(raw['order']);
    final missing = DownloadPageAction.values
        .where((action) => !order.contains(action))
        .toList();
    final enabled = parseList(raw['enabled']);
    order.addAll(missing);
    enabled.addAll(missing);
    final outside =
        raw.containsKey('externalAction') && raw['externalAction'] == null
            ? null
            : parse(raw['externalAction']) ?? DownloadPageAction.search;
    return DownloadPageActionsConfig._(order, enabled, outside);
  }

  Iterable<DownloadPageAction> get menuActions => order
      .where((action) => action != externalAction && enabled.contains(action));
  bool get showExternal =>
      externalAction != null && enabled.contains(externalAction);

  DownloadPageActionsConfig toggle(DownloadPageAction action, bool value) =>
      DownloadPageActionsConfig._(
          order,
          value
              ? {...enabled, action}
              : enabled.where((item) => item != action),
          externalAction);
  DownloadPageActionsConfig withExternal(DownloadPageAction? action) =>
      DownloadPageActionsConfig._(order, enabled, action);

  /// onReorderItem provides an already normalized destination.
  DownloadPageActionsConfig reorder(int oldIndex, int newIndex) {
    final next = List.of(order);
    next.insert(newIndex, next.removeAt(oldIndex));
    return DownloadPageActionsConfig._(next, enabled, externalAction);
  }

  Map<String, Object?> toJson() => {
        'order': order.map((action) => action.name).toList(),
        'enabled':
            order.where(enabled.contains).map((action) => action.name).toList(),
        'externalAction': externalAction?.name,
      };
}
