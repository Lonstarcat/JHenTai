/// Converts counts/bytes to Android's Int32 progress range without changing
/// the underlying task. Small page/item counts retain their original values.
({int max, int progress, bool indeterminate}) notificationProgress({
  required int current,
  required int total,
}) {
  if (total <= 0) {
    return (max: 0, progress: 0, indeterminate: true);
  }
  final int clampedCurrent = current.clamp(0, total);
  const int scale = 10000;
  if (total <= scale) {
    return (max: total, progress: clampedCurrent, indeterminate: false);
  }

  // BigInt avoids overflowing Dart's native Int64 during multiplication, even
  // for counters near Int64.MAX_VALUE. Never scale the real download counters.
  final int progress =
      ((BigInt.from(clampedCurrent) * BigInt.from(scale)) ~/ BigInt.from(total))
          .toInt();
  return (max: scale, progress: progress, indeterminate: false);
}
