import '../model/background_task_info.dart';

enum NotificationTaskStage { paused, waiting, working, transferring }

/// Presentation-only observations; this never changes download scheduling.
class NotificationTaskCandidate {
  final BackgroundTaskInfo task;
  final NotificationTaskStage stage;
  final bool canTransfer;
  final int transferredBytes;
  final int priority;

  const NotificationTaskCandidate({
    required this.task,
    required this.stage,
    this.canTransfer = false,
    this.transferredBytes = 0,
    this.priority = 0,
  });
}

class _TransferObservation {
  int bytes;
  int current;
  DateTime? lastTransfer;

  _TransferObservation(this.bytes, this.current);
}

/// Keep the primary stable within its activity tier, not at the mercy of a
/// recently queued task or momentary speed fluctuations. A short stall retains
/// priority for three seconds; a new real transfer can then take over.
class BackgroundNotificationSelector {
  final DateTime Function() _now;
  final Map<String, _TransferObservation> _observations = {};
  final Map<BackgroundTaskType, String> _representatives = {};
  String? _primaryId;

  BackgroundNotificationSelector({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  List<BackgroundTaskInfo> select(
    List<NotificationTaskCandidate> candidates, {
    String? preferredId,
  }) {
    final ids = candidates.map((item) => item.task.id).toSet();
    _observations.removeWhere((id, _) => !ids.contains(id));
    if (candidates.isEmpty) {
      _primaryId = null;
      _representatives.clear();
      return const [];
    }
    final now = _now();
    final ranks = <String, int>{};
    for (final item in candidates) {
      var rank = item.stage.index;
      if (item.canTransfer && rank >= NotificationTaskStage.working.index) {
        final observation = _observations.putIfAbsent(
          item.task.id,
          () => _TransferObservation(item.transferredBytes, item.task.current),
        );
        final moving = (item.task.speedBytesPerSecond ?? 0) > 0 ||
            item.transferredBytes > observation.bytes ||
            item.task.current > observation.current;
        if (moving) {
          observation.lastTransfer = now;
        }
        observation.bytes = item.transferredBytes;
        observation.current = item.task.current;
        if (observation.lastTransfer != null) {
          rank = now.difference(observation.lastTransfer!) <=
                  const Duration(seconds: 3)
              ? 4
              : NotificationTaskStage.transferring.index;
        }
      } else {
        // Pausing/waiting invalidates evidence from an earlier transfer.
        _observations.remove(item.task.id);
      }
      ranks[item.task.id] = rank;
    }
    int compare(NotificationTaskCandidate a, NotificationTaskCandidate b,
        String? currentId) {
      final rank = ranks[b.task.id]!.compareTo(ranks[a.task.id]!);
      if (rank != 0) {
        return rank;
      }
      if (a.task.id == currentId) {
        return b.task.id == currentId ? 0 : -1;
      }
      if (b.task.id == currentId) {
        return 1;
      }
      if (a.task.id == preferredId) {
        return b.task.id == preferredId ? 0 : -1;
      }
      if (b.task.id == preferredId) {
        return 1;
      }
      return a.priority.compareTo(b.priority);
    }

    // Dart's sort is not stable: use source order as the final tie-breaker.
    final order = {
      for (var i = 0; i < candidates.length; i++) candidates[i].task.id: i
    };
    NotificationTaskCandidate choose(
        List<NotificationTaskCandidate> pool, String? currentId) {
      return pool.reduce((a, b) {
        final result = compare(a, b, currentId);
        return result < 0 ||
                (result == 0 && order[a.task.id]! < order[b.task.id]!)
            ? a
            : b;
      });
    }

    final primary = choose(candidates, _primaryId);
    _primaryId = primary.task.id;
    final selected = <BackgroundTaskInfo>[primary.task];
    for (final type in BackgroundTaskType.values) {
      final pool = candidates.where((item) => item.task.type == type).toList();
      if (pool.isEmpty) {
        _representatives.remove(type);
        continue;
      }
      final representative = primary.task.type == type
          ? primary
          : choose(pool, _representatives[type]);
      _representatives[type] = representative.task.id;
      if (representative.task.id != primary.task.id) {
        selected.add(representative.task);
      }
    }
    return selected;
  }
}
