import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/utils/notification_progress_util.dart';

void main() {
  const int gib = 1024 * 1024 * 1024;

  test('unknown totals are indeterminate with safe zero values', () {
    for (final total in [0, -1, -gib]) {
      expect(notificationProgress(current: gib, total: total),
          (max: 0, progress: 0, indeterminate: true));
    }
  });

  test('small page/item counts remain exact and are clamped', () {
    for (final total in [1, 5, 48, 100, 10000]) {
      for (final current in [-1, 0, 1, total ~/ 2, total, total + 1]) {
        expect(notificationProgress(current: current, total: total), (
          max: total,
          progress: current.clamp(0, total),
          indeterminate: false
        ));
      }
    }
  });

  test('screenshot archive ratio remains about 61.7 percent', () {
    final result = notificationProgress(
        current: (2.91 * gib).round(), total: (4.72 * gib).round());
    expect(result, (max: 10000, progress: 6165, indeterminate: false));
    expect(result.progress / result.max, closeTo(2.91 / 4.72, .0001));
  });

  test('Int32 and multi-GiB boundaries stay bounded and monotonic', () {
    for (final total in [
      10001,
      0x7ffffffe,
      0x7fffffff,
      0x80000000,
      4 * gib - 1,
      4 * gib,
      4 * gib + 1,
      10 * gib,
      100 * gib,
      0x7fffffffffffffff,
    ]) {
      int previous = -1;
      for (final current in [
        -1,
        0,
        1,
        total ~/ 4,
        total ~/ 2,
        total - 1,
        total,
      ]) {
        final result = notificationProgress(current: current, total: total);
        final expected =
            ((BigInt.from(current.clamp(0, total)) * BigInt.from(10000)) ~/
                    BigInt.from(total))
                .toInt();
        expect(result.max, 10000);
        expect(result.progress, expected);
        expect(result.progress, inInclusiveRange(previous, result.max));
        expect(result.indeterminate, isFalse);
        previous = result.progress;
      }
      expect(
          notificationProgress(current: 0x7fffffffffffffff, total: total)
              .progress,
          10000);
    }
  });
}
