import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/model/download_multi_select_toolbar.dart';
import 'package:jhentai/src/setting/style_setting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const gallery = DownloadToolbarKind.gallery;
  const archive = DownloadToolbarKind.archive;

  test('all four production select-all handlers refresh the bottom toolbar',
      () {
    for (final path in [
      'lib/src/pages/download/grid/gallery/gallery_grid_download_page_logic.dart',
      'lib/src/pages/download/grid/archive/archive_grid_download_page_logic.dart',
      'lib/src/pages/download/list/gallery/gallery_list_download_page_logic.dart',
      'lib/src/pages/download/list/archive/archive_list_download_page_logic.dart',
    ]) {
      final source = File(path).readAsStringSync();
      final start = source.indexOf('selectAllItem()');
      final end = source.indexOf('\n  }', start);
      expect(source.substring(start, end), contains('bottomAppbarId'),
          reason: path);
    }
  });

  test(
      'defaults preserve original order, archive-only source and stable strings',
      () {
    expect(DownloadToolbarConfig.defaults(gallery).toJson()['order'], [
      'selectAll',
      'resume',
      'pause',
      'batchUpdate',
      'favorite',
      'changeGroup',
      'delete'
    ]);
    expect(DownloadToolbarConfig.defaults(archive).order.last,
        DownloadToolbarAction.changeParseSource);
    final settings = StyleSetting();
    final oldJson = jsonDecode(settings.toConfigString()) as Map;
    oldJson.remove('galleryMultiSelectToolbar');
    oldJson.remove('archiveMultiSelectToolbar');
    settings.applyBeanConfig(jsonEncode(oldJson));
    expect(settings.galleryToolbar.value.visible.length, 7);
    expect(settings.archiveToolbar.value.visible.length, 8);
  });

  test('malformed, unknown, duplicate, cross-scope and missing IDs sanitize',
      () {
    for (final malformed in [null, 1, 'broken', []]) {
      expect(
          DownloadToolbarConfig.fromJson(malformed, gallery).visible.length, 7);
    }
    final config = DownloadToolbarConfig.fromJson({
      'order': ['delete', 'delete', 'alien', 42, 'changeParseSource'],
      'enabled': ['delete', 'alien'],
    }, gallery);
    expect(config.order.first, DownloadToolbarAction.delete);
    expect(config.order.length, 7);
    expect(config.order.toSet().length, 7);
    expect(config.visible.length, 7); // missing IDs receive current defaults
    expect(
        config.order, isNot(contains(DownloadToolbarAction.changeParseSource)));
    expect(
        DownloadToolbarConfig.fromJson(
                {'order': 'bad', 'enabled': 'bad'}, archive)
            .visible
            .length,
        8);
  });

  test(
      'all-off is valid; toggle retains position, downward reorder round-trips',
      () {
    var config = DownloadToolbarConfig.defaults(archive).reorder(0, 7);
    for (final action in config.order) {
      config = config.toggle(action, false);
    }
    final read = DownloadToolbarConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())), archive);
    expect(read.visible, isEmpty);
    expect(read.order.last, DownloadToolbarAction.selectAll);
    expect(read.toggle(DownloadToolbarAction.selectAll, true).visible.single,
        DownloadToolbarAction.selectAll);
    expect(read.order, config.order);
  });

  test('bad toolbar section does not alter unrelated style settings', () {
    final settings = StyleSetting();
    final data = jsonDecode(settings.toConfigString()) as Map;
    data['showTagIcons'] = true;
    data['galleryMultiSelectToolbar'] = 'broken';
    data['archiveMultiSelectToolbar'] = {
      'order': ['favorite'],
      'enabled': []
    };
    settings.applyBeanConfig(jsonEncode(data));
    expect(settings.showTagIcons.value, isTrue);
    expect(settings.galleryToolbar.value.visible.length, 7);
    expect(settings.archiveToolbar.value.visible,
        isNot(contains(DownloadToolbarAction.favorite)));
  });

  test(
      'old custom order adds batch update without changing hidden buttons or other scope',
      () {
    final config = DownloadToolbarConfig.fromJson({
      'order': [
        'delete',
        'selectAll',
        'resume',
        'pause',
        'favorite',
        'changeGroup'
      ],
      'enabled': ['selectAll'],
    }, gallery);
    expect(config.order.last, DownloadToolbarAction.batchUpdate);
    expect(config.visible,
        [DownloadToolbarAction.selectAll, DownloadToolbarAction.batchUpdate]);
    expect(config.toggle(DownloadToolbarAction.batchUpdate, false).visible,
        [DownloadToolbarAction.selectAll]);
  });

  test('serialized writes: failure rollback precedes next edit, queue survives',
      () async {
    final gate = Completer<void>();
    final seen = <Map>[];
    final settings = StyleSetting(configWriter: (json) async {
      seen.add(jsonDecode(json) as Map);
      if (seen.length == 1) {
        await gate.future;
        throw StateError('synthetic failure');
      }
      return 1;
    });
    final first = settings.updateToolbar(gallery,
        (config) => config.toggle(DownloadToolbarAction.delete, false));
    final failed = expectLater(first, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(settings.galleryToolbar.value.enabled,
        isNot(contains(DownloadToolbarAction.delete)));
    final second = settings.updateToolbar(
        gallery, (config) => config.toggle(DownloadToolbarAction.pause, false));
    expect(seen.length, 1);
    gate.complete();
    await failed;
    await second;
    expect(seen.length, 2);
    expect(settings.galleryToolbar.value.enabled,
        contains(DownloadToolbarAction.delete));
    expect(settings.galleryToolbar.value.enabled,
        isNot(contains(DownloadToolbarAction.pause)));
    expect(settings.savingToolbar.value, isFalse);
  });

  test(
      'zero-result rolls back; subsequent general style write excludes failed edit',
      () async {
    final gate = Completer<void>();
    final seen = <Map>[];
    final settings = StyleSetting(configWriter: (json) async {
      seen.add(jsonDecode(json) as Map);
      if (seen.length == 1) {
        await gate.future;
        return 0;
      }
      return 1;
    });
    final first = settings.updateToolbar(archive,
        (config) => config.toggle(DownloadToolbarAction.favorite, false));
    final failure = expectLater(first, throwsStateError);
    final general = settings.saveBeanConfig();
    gate.complete();
    await failure;
    await general;
    expect(settings.archiveToolbar.value.enabled,
        contains(DownloadToolbarAction.favorite));
    expect((seen.last['archiveMultiSelectToolbar'] as Map)['enabled'],
        contains('favorite'));
  });

  test('gallery and archive edits, resets and serialization remain independent',
      () async {
    final settings = StyleSetting(configWriter: (_) async => 1);
    await settings.updateToolbar(gallery,
        (config) => config.toggle(DownloadToolbarAction.delete, false));
    await settings.updateToolbar(archive, (config) => config.reorder(7, 0));
    expect(settings.galleryToolbar.value.enabled,
        isNot(contains(DownloadToolbarAction.delete)));
    expect(settings.archiveToolbar.value.enabled,
        contains(DownloadToolbarAction.delete));
    await settings.updateToolbar(
        gallery, (_) => DownloadToolbarConfig.defaults(gallery));
    expect(settings.archiveToolbar.value.order.first,
        DownloadToolbarAction.changeParseSource);
    final restored = StyleSetting()..applyBeanConfig(settings.toConfigString());
    expect(restored.archiveToolbar.value.order,
        settings.archiveToolbar.value.order);
    expect(restored.galleryToolbar.value.visible.length, 7);
  });
}
