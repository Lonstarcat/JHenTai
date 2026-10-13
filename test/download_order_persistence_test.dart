import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/utils/download_order_persistence_util.dart';
import 'package:jhentai/src/pages/download/list/widget/download_reorder_widgets.dart';

void main() {
  test('canonical order writes only moved range, normalized downward index', () {
    final entries = [for (int i = 0; i < 10; i++) (id: i, order: i)];
    final moved = reorderDownloadList(entries, 2, 7);
    final changes = changedDownloadOrders(moved, (entry) => entry.id, (entry) => entry.order);
    expect(changes, {3: 2, 4: 3, 5: 4, 6: 5, 7: 6, 2: 7});
  });
  test('legacy duplicate/sparse and title order canonicalize safely', () {
    final entries = [(id: 1, order: 0), (id: 2, order: 0), (id: 3, order: 50)];
    expect(changedDownloadOrders(entries, (entry) => entry.id, (entry) => entry.order), {2: 1, 3: 2});
    expect(
        changedDownloadOrders(
            [(id: 3, order: 2), (id: 1, order: 0), (id: 2, order: 1)], (entry) => entry.id, (entry) => entry.order),
        {3: 0, 1: 1, 2: 2});
  });
  test('writes serialize and capture immutable values', () async {
    final writer = DownloadOrderWriter();
    final gate = Completer<void>();
    final seen = <Map<int, int>>[];
    final firstValues = {1: 0, 2: 1};
    final first = writer.save(firstValues, (values) async {
      seen.add(values);
      await gate.future;
    });
    firstValues[1] = 99;
    final second = writer.save({1: 1, 2: 0}, (values) async {
      seen.add(values);
    });
    await Future<void>.delayed(Duration.zero);
    expect(seen, [
      {1: 0, 2: 1}
    ]);
    gate.complete();
    await Future.wait([first, second]);
    expect(seen, [
      {1: 0, 2: 1},
      {1: 1, 2: 0}
    ]);
  });
  test('failed subset retries with next disjoint subset without poisoning queue', () async {
    final writer = DownloadOrderWriter();
    final first = writer.save({1: 0}, (_) async {
      throw StateError('synthetic failure');
    });
    await expectLater(first, throwsStateError);
    Map<int, int>? actual;
    await writer.save({2: 1}, (values) async {
      actual = values;
    });
    expect(actual, {1: 0, 2: 1});
    await writer.save({3: 2}, (values) async {
      actual = values;
    });
    expect(actual, {3: 2});
  });
}
