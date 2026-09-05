import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/utils/download_task_locator_util.dart';

void main() {
  testWidgets('reveals a task that starts outside a lazy list viewport',
      (tester) async {
    final ScrollController controller = ScrollController();
    final GlobalKey targetKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            itemCount: 100,
            itemExtent: 100,
            itemBuilder: (_, index) => SizedBox(
              key: index == 80 ? targetKey : null,
              height: 100,
            ),
          ),
        ),
      ),
    );

    bool? result;
    revealDownloadTask(
      controller: controller,
      itemKey: targetKey,
      estimatedOffset: 8000,
    ).then((value) => result = value);

    for (int i = 0; i < 20 && result == null; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(result, isTrue);
    expect(targetKey.currentContext, isNotNull);
    expect(controller.offset, greaterThan(7000));
    controller.dispose();
  });

  test('list task offset skips items in collapsed groups', () {
    final double offset = downloadListTaskOffset(
      groups: const ['A', 'B', 'C'],
      expandedGroups: const {'A', 'C'},
      targetGroup: 'C',
      targetIndex: 2,
      itemCount: (group) => {'A': 3, 'B': 7, 'C': 4}[group]!,
      groupExtent: 60,
      itemExtent: 140,
    );

    expect(offset, 60 + 3 * 140 + 60 + 60 + 2 * 140);
  });

  test('grid task offset includes the fixed return tile', () {
    final double offset = downloadGridTaskOffset(
      itemIndex: 5,
      crossAxisCount: 3,
      availableWidth: 552,
      crossAxisSpacing: 12,
      mainAxisSpacing: 24,
      childAspectRatio: 0.8,
    );

    expect(offset, 244);
  });

  test('grid cross axis count follows max extent delegate behavior', () {
    expect(
      downloadGridCrossAxisCount(
        availableWidth: 552,
        configuredCount: null,
        maxCrossAxisExtent: 180,
        crossAxisSpacing: 12,
      ),
      3,
    );
    expect(
      downloadGridCrossAxisCount(
        availableWidth: 552,
        configuredCount: 4,
        maxCrossAxisExtent: 180,
        crossAxisSpacing: 12,
      ),
      4,
    );
  });
}
