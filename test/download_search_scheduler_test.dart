import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/pages/download_search/download_search_scheduler.dart';

void main() {
  testWidgets('debounces and executes only the latest request', (tester) async {
    DownloadSearchScheduler scheduler = DownloadSearchScheduler(delay: const Duration(milliseconds: 300));
    List<String> calls = [];

    scheduler.schedule((_) async => calls.add('first'));
    await tester.pump(const Duration(milliseconds: 200));
    scheduler.schedule((_) async => calls.add('second'));
    await tester.pump(const Duration(milliseconds: 299));
    expect(calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, ['second']);
  });

  testWidgets('cancel prevents a pending request and invalidates a running request', (tester) async {
    DownloadSearchScheduler scheduler = DownloadSearchScheduler(delay: const Duration(milliseconds: 1));
    int? requestId;

    scheduler.schedule((id) async => requestId = id);
    await tester.pump(const Duration(milliseconds: 1));
    expect(requestId, isNotNull);
    expect(scheduler.isCurrent(requestId!), isTrue);

    scheduler.cancel();
    expect(scheduler.isCurrent(requestId!), isFalse);

    bool called = false;
    scheduler.schedule((_) async => called = true);
    scheduler.cancel();
    await tester.pump(const Duration(milliseconds: 1));
    expect(called, isFalse);
  });

  testWidgets('dispose prevents callbacks and state updates', (tester) async {
    DownloadSearchScheduler scheduler = DownloadSearchScheduler(delay: const Duration(milliseconds: 300));
    int? requestId;
    bool called = false;

    scheduler.schedule((id) async {
      requestId = id;
      called = true;
    });
    scheduler.dispose();
    await tester.pump(const Duration(milliseconds: 300));

    expect(called, isFalse);
    expect(requestId, isNull);
  });
}
