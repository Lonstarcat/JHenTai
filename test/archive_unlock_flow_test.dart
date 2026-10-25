import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/exception/eh_site_exception.dart';
import 'package:jhentai/src/model/archive_unlock_result.dart';
import 'package:jhentai/src/network/eh_request.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/service/log.dart';
import 'package:jhentai/src/service/isolate_service.dart';
import 'package:jhentai/src/utils/archive_page_poller.dart';
import 'package:jhentai/src/utils/eh_spider_parser.dart';
import 'package:jhentai/src/utils/speed_computer.dart';

// Synthetic markup; the waiting copy is documented by EhSyringe's archiver
// translation resource, not captured from a user's paid archive session.
const pending =
    '<html><body><div id="continue">Locating archive server and preparing file for download... (this can take several minutes)</div></body></html>';
const ready =
    '<html><body><div id="continue"><p><a href="https://archive-test.hath.network/file">Continue</a></p></div></body></html>';

ArchiveUnlockResult parsePage(String html, {Headers? headers}) =>
    EHSpiderParser.unlockArchivePage2DownloadArchivePageUrl(
        headers ?? Headers(), html);

class QuietArchiveLog extends LogService {
  @override
  void download(Object msg, [bool withStack = false]) {}
  @override
  void info(Object msg, [bool withStack = false]) {}
}

// Exercise the real parser without starting the app's isolate lifecycle.
// HTTP requests below still use the production EHRequest and a loopback server.
class InlineParserIsolate extends IsolateService {
  @override
  Future<R> run<Q, R>(FutureOr<R> Function(Q) callback, Q message,
          {String? debugLabel}) async =>
      callback(message);
}

class MemoryArchiveService extends ArchiveDownloadService {
  final List<String> errors;
  int statusUpdates = 0;
  MemoryArchiveService(
      Future<ArchiveUnlockResult> Function(ArchiveDownloadedData, CancelToken)?
          request,
      this.errors,
      {Future<void> Function(int)? persist,
      ArchivePagePoller poller =
          const ArchivePagePoller(interval: Duration.zero)})
      : super(
            archivePageRequester: request,
            archiveStatusWriter: persist ?? (_) async {},
            archivePageErrorReporter: errors.add,
            archivePagePoller: poller);

  @override
  void update([List<Object>? ids, bool condition = true]) {
    statusUpdates++;
    super.update(ids, condition);
  }

  @override
  Future<void> pauseDownloadArchive(int gid,
      {bool needReUnlock = false}) async {
    final info = archiveDownloadInfos[gid]!;
    info.cancelToken.cancel();
    info.cancelToken = CancelToken();
    info.archiveStatus = ArchiveStatus.paused;
  }
}

ArchiveDownloadInfo info(
        {ArchiveStatus status = ArchiveStatus.unlocking, int source = 0}) =>
    ArchiveDownloadInfo(
        size: 1,
        parseSource: source,
        archiveStatus: status,
        cancelToken: CancelToken(),
        speedComputer: SpeedComputer(),
        sortOrder: 0,
        group: 'test');

const archive = ArchiveDownloadedData(
    gid: 1,
    token: 'test',
    title: 'Test archive',
    category: 'Manga',
    pageCount: 1,
    galleryUrl: 'https://example.invalid/g/1/test',
    coverUrl: 'https://example.invalid/cover',
    size: 1,
    publishTime: '2026-10-22',
    archiveStatusCode: 30,
    archivePageUrl: 'https://example.invalid/archiver.php?gid=1',
    isOriginal: true,
    insertTime: '2026-10-22',
    sortOrder: 0,
    groupName: 'test',
    tags: '{}',
    parseSource: 1);

void main() {
  late LogService originalLog;
  setUp(() {
    originalLog = log;
    log = QuietArchiveLog();
  });
  tearDown(() {
    log = originalLog;
  });

  test('real parser distinguishes ready, exact official pending and errors',
      () {
    expect(parsePage(ready).state, ArchiveUnlockState.ready);
    expect(
        parsePage(ready.replaceFirst(
                '</body>', '<input value="Insufficient Funds"></body>'))
            .state,
        ArchiveUnlockState.ready);
    expect(
        parsePage(
                '<div id="continue"><a href="https://unexpected.invalid/file">Continue</a></div>')
            .state,
        ArchiveUnlockState.error);
    expect(parsePage(pending).state, ArchiveUnlockState.pending);
    expect(parsePage(pending.replaceAll(' ', '\n ')).state,
        ArchiveUnlockState.pending);
    for (final html in [
      '',
      '\uFFFD\uFFFD compressed bytes',
      '<h1>Server error</h1>',
      '<p>Please wait...</p>',
      '<form><input type="password"></form>',
      '<p>You do not have enough funds to download this archive.</p>',
      '<div id="continue"><a href="javascript:alert(1)">Continue</a></div>',
      '<div id="continue"><a href="http://example.invalid/file">Continue</a></div>'
    ]) {
      expect(parsePage(html).state, ArchiveUnlockState.error, reason: html);
    }
    expect(() => parsePage('<title>Just a moment...</title>'),
        throwsA(isA<EHSiteException>()));
    expect(
        () => parsePage(ready,
            headers: Headers.fromMap({
              'cf-mitigated': ['challenge']
            })),
        throwsA(isA<EHSiteException>()));
    expect(
        parsePage(ready,
            headers: Headers.fromMap({
              'content-encoding': ['br']
            })).state,
        ArchiveUnlockState.error);
  });

  test(
      'upstream unlock POST uses original/resample forms and parses gzip/plain HTML',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final methods = <String>[];
    final listener = server.listen((request) async {
      methods.add(request.method);
      expect(request.method, 'POST');
      expect(request.headers.value('user-agent'), isNot(contains('IntelliJ')));
      final body = await utf8.decoder.bind(request).join();
      final original = methods.length <= 2;
      final form = Uri.splitQueryString(body);
      expect(form, {
        'dltype': original ? 'org' : 'res',
        'dlcheck': original
            ? 'Download Original Archive'
            : 'Download Resample Archive',
      });
      expect(request.headers.contentType?.mimeType,
          'application/x-www-form-urlencoded');
      expect(request.contentLength, utf8.encode(body).length);
      request.response.headers.contentType = ContentType.html;
      if (methods.length.isOdd) {
        request.response.headers.set('content-encoding', 'gzip');
        request.response.add(gzip.encode(utf8.encode(pending)));
      } else {
        request.response.write(ready);
      }
      await request.response.close();
    });
    final dio = Dio();
    final client = EHRequest.forTesting(dio);
    try {
      final url = 'http://127.0.0.1:${server.port}/archiver.php';
      for (final original in [true, false]) {
        final unlock = await client.requestUnlockArchive<Response>(
            url: url, isOriginal: original);
        expect(
            EHSpiderParser.unlockArchivePage2DownloadArchivePageUrl(
                    unlock.headers, unlock.data)
                .state,
            ArchiveUnlockState.pending);
        final preparation = await client.requestUnlockArchive<Response>(
            url: url, isOriginal: original);
        expect(
            EHSpiderParser.unlockArchivePage2DownloadArchivePageUrl(
                    preparation.headers, preparation.data)
                .state,
            ArchiveUnlockState.ready);
      }
      expect(methods, ['POST', 'POST', 'POST', 'POST']);
    } finally {
      dio.close(force: true);
      await server.close(force: true);
      await listener.cancel();
    }
  });

  test('production stages pending->ready reuse the upstream unlock request',
      () async {
    var calls = 0;
    final errors = <String>[];
    final service = MemoryArchiveService((_, __) async {
      return parsePage(++calls < 3 ? pending : ready);
    }, errors)
      ..archives.add(archive)
      ..archiveDownloadInfos[1] = info();
    await service.resolveArchivePageForTesting(archive);
    expect(calls, 3);
    expect(service.archiveDownloadInfos[1]!.archiveStatus,
        ArchiveStatus.parsedDownloadPageUrl);
    expect(service.archiveDownloadInfos[1]!.downloadPageUrl,
        'https://archive-test.hath.network/file');
    expect(errors, isEmpty);
  });

  test(
      'preparation pipeline really sends upstream POSTs, not GET status checks',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final methods = <String>[];
    final listener = server.listen((request) async {
      methods.add(request.method);
      final form =
          Uri.splitQueryString(await utf8.decoder.bind(request).join());
      expect(form['dltype'], 'org');
      expect(form['dlcheck'], 'Download Original Archive');
      request.response.headers.contentType = ContentType.html;
      request.response.write(methods.length < 3 ? pending : ready);
      await request.response.close();
    });
    final previousClient = ehRequest;
    final previousIsolate = isolateService;
    final dio = Dio();
    ehRequest = EHRequest.forTesting(dio);
    isolateService = InlineParserIsolate();
    final errors = <String>[];
    final target = archive.copyWith(
        archivePageUrl: 'http://127.0.0.1:${server.port}/archiver.php');
    final service = MemoryArchiveService(null, errors)
      ..archives.add(target)
      ..archiveDownloadInfos[1] = info();
    try {
      await service.resolveArchivePageForTesting(target);
      expect(methods, ['POST', 'POST', 'POST']);
      expect(service.archiveDownloadInfos[1]!.archiveStatus,
          ArchiveStatus.parsedDownloadPageUrl);
      expect(errors, isEmpty);
    } finally {
      ehRequest = previousClient;
      isolateService = previousIsolate;
      dio.close(force: true);
      await server.close(force: true);
      await listener.cancel();
    }
  });

  test('unknown pages and network errors pause without automatic POST retries',
      () async {
    for (final failOnPost in [false, true]) {
      for (final networkError in [false, true]) {
        var calls = 0;
        final errors = <String>[];
        final service = MemoryArchiveService((_, __) async {
          calls++;
          if (calls == 1 && !failOnPost) {
            return parsePage(pending);
          }
          if (networkError) {
            throw DioException.connectionError(
                requestOptions: RequestOptions(), reason: 'offline test');
          }
          return parsePage('<h1>Unexpected form</h1>');
        }, errors)
          ..archives.add(archive)
          ..archiveDownloadInfos[1] = info();
        await service.resolveArchivePageForTesting(archive);
        expect(calls, failOnPost ? 1 : 2);
        expect(service.archiveDownloadInfos[1]!.archiveStatus,
            ArchiveStatus.paused);
        expect(errors, hasLength(1));
      }
    }
  });

  test('pending attempt limit and total timeout pause the production task',
      () async {
    for (final slow in [false, true]) {
      final errors = <String>[];
      var calls = 0;
      final service = MemoryArchiveService((_, __) async {
        calls++;
        if (slow && calls > 1) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        return parsePage(pending);
      }, errors,
          poller: ArchivePagePoller(
              maxAttempts: 2,
              timeout: Duration(milliseconds: slow ? 10 : 1000),
              interval: Duration.zero))
        ..archives.add(archive)
        ..archiveDownloadInfos[1] = info();
      await service.resolveArchivePageForTesting(archive);
      expect(calls, slow ? 2 : 3);
      expect(
          service.archiveDownloadInfos[1]!.archiveStatus, ArchiveStatus.paused);
      expect(errors, hasLength(1));
    }
  });

  test(
      'cancel during delay and stale ready response cannot overwrite a replacement',
      () async {
    for (final duringDelay in [true, false]) {
      final response = Completer<ArchiveUnlockResult>();
      final started = Completer<void>();
      final errors = <String>[];
      var calls = 0;
      final service = MemoryArchiveService((_, __) async {
        if (++calls == 1) {
          return parsePage(pending);
        }
        started.complete();
        if (duringDelay) {
          return parsePage(pending);
        }
        return response.future;
      }, errors,
          poller: const ArchivePagePoller(interval: Duration(seconds: 10)))
        ..archives.add(archive)
        ..archiveDownloadInfos[1] = info();
      final running = service.resolveArchivePageForTesting(archive);
      await started.future;
      await Future<void>.delayed(Duration.zero);
      final old = service.archiveDownloadInfos[1]!;
      old.cancelToken.cancel();
      final replacement = info(status: ArchiveStatus.unlocking);
      service.archiveDownloadInfos[1] = replacement;
      if (!duringDelay) {
        response.complete(parsePage(ready));
      }
      await running.timeout(const Duration(seconds: 1));
      expect(replacement.downloadPageUrl, isNull);
      expect(replacement.archiveStatus, ArchiveStatus.unlocking);
      expect(errors, isEmpty);
    }
  });

  test('deleted task and replaced token discard a late first unlock response',
      () async {
    for (final remove in [true, false]) {
      final response = Completer<ArchiveUnlockResult>();
      final errors = <String>[];
      var calls = 0;
      final service = MemoryArchiveService((_, __) {
        calls++;
        return response.future;
      }, errors)
        ..archives.add(archive)
        ..archiveDownloadInfos[1] = info();
      final running = service.resolveArchivePageForTesting(archive);
      if (remove) {
        service.archiveDownloadInfos.remove(1);
      } else {
        service.archiveDownloadInfos[1]!.cancelToken = CancelToken();
      }
      response.complete(parsePage(ready));
      await running;
      expect(calls, 1);
      expect(service.archiveDownloadInfos[1]?.downloadPageUrl, isNull);
      expect(errors, isEmpty);
    }
  });

  test(
      'replacement during database await receives no stale status or UI update',
      () async {
    for (final replaceObject in [true, false]) {
      final writing = Completer<void>();
      final releaseWrite = Completer<void>();
      final service = MemoryArchiveService(
          (_, __) async => parsePage(ready), [], persist: (_) {
        writing.complete();
        return releaseWrite.future;
      })
        ..archives.add(archive)
        ..archiveDownloadInfos[1] = info();
      final running = service.resolveArchivePageForTesting(archive);
      await writing.future;
      if (replaceObject) {
        service.archiveDownloadInfos[1] = info();
      } else {
        service.archiveDownloadInfos[1]!.cancelToken = CancelToken();
      }
      releaseWrite.complete();
      await running;
      expect(service.statusUpdates, 0);
      if (replaceObject) {
        expect(service.archiveDownloadInfos[1]!.downloadPageUrl, isNull);
        expect(service.archiveDownloadInfos[1]!.archiveStatus,
            ArchiveStatus.unlocking);
      }
    }
  });

  test('bot and already-known page URL skip all unlock requests', () async {
    for (final bot in [true, false]) {
      final service = MemoryArchiveService(
          (_, __) => throw StateError('unexpected network'), [])
        ..archives.add(archive)
        ..archiveDownloadInfos[1] = info(source: bot ? 1 : 0);
      if (!bot) {
        service.archiveDownloadInfos[1]!.downloadPageUrl =
            'https://archive.example.invalid/known';
      }
      await service.resolveArchivePageForTesting(archive);
      expect(service.archiveDownloadInfos[1]!.archiveStatus,
          ArchiveStatus.parsedDownloadPageUrl);
    }
  });
}
