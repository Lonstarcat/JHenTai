import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/widget/batch_update_statistics.dart';

void main() {
  for (final width in [224.0, 580.0]) {
    testWidgets(
        'statistics align into ${width < 300 ? 2 : 3} columns at $width',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
              body: SizedBox(
                  width: width,
                  child: const BatchUpdateStatistics(items: [
                    BatchUpdateStatistic('Size', '123 MB', Icons.storage),
                    BatchUpdateStatistic('Count', '12345', Icons.update),
                    BatchUpdateStatistic('GP', '1000000', Icons.toll),
                    BatchUpdateStatistic('Bot GP', '2000000', Icons.smart_toy),
                  ])))));
      final firstY = tester.getTopLeft(find.text('Size')).dy;
      expect(tester.getTopLeft(find.text('Count')).dy, firstY);
      if (width < 300) {
        expect(tester.getTopLeft(find.text('GP')).dy, greaterThan(firstY));
      } else {
        expect(tester.getTopLeft(find.text('GP')).dy, firstY);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('long localized labels force two columns even on wide layout',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 580,
                child: BatchUpdateStatistics(items: [
                  BatchUpdateStatistic(
                      'A very long localized update count label',
                      '5000',
                      Icons.update),
                  BatchUpdateStatistic('Total size', '123 MB', Icons.storage),
                  BatchUpdateStatistic('GP', '1000000', Icons.toll),
                ])))));
    expect(tester.getTopLeft(find.text('GP')).dy,
        greaterThan(tester.getTopLeft(find.text('Total size')).dy));
    expect(tester.takeException(), isNull);
  });
}
