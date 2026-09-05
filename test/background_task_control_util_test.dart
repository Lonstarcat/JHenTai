import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/utils/background_task_control_util.dart';

void main() {
  test('manual task replaces the previous notification resume target', () {
    final Set<int> controlledGids = <int>{101, 102};

    replaceNotificationResumeTarget(controlledGids, 203);

    expect(controlledGids, <int>{203});
  });
}
