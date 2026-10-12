import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/utils/tag_rich_label_parser.dart';

const iconUrl =
    'https://raw.githubusercontent.com/wiki/EhTagTranslation/Database/database-icon/pokemon.webp';

void main() {
  test(
      'real translation entries in the reported screenshot retain their image tokens',
      () {
    const labels = [
      '<p><img src="https://raw.githubusercontent.com/wiki/EhTagTranslation/Database/database-icon/pokemon.webp" alt="精灵球图标">宝可梦</p>',
      '<p><img src="https://lain.bgm.tv/r/400/pic/cover/l/56/33/208559_6jzc1.jpg"> 碧蓝航线</p>',
      '<p><img src="https://p.sda1.dev/5/d3c970768e4b7e4d63ead4e46f28aa03/1.jpg" alt="icon">原神</p>',
      '<p><img src="https://bluearchive.nexon.com/favicon.ico">蔚蓝档案</p>',
    ];
    for (final label in labels) {
      final tokens = TagRichLabelParser.parse(label);
      expect(tokens.whereType<TagLabelImage>().length, 1);
      expect(
          tokens
              .whereType<TagLabelText>()
              .any((token) => token.text.trim().isNotEmpty),
          isTrue);
    }
  });

  test('preserves text, Emoji, entities and ordered inline images', () {
    final tokens = TagRichLabelParser.parse(
        '<p>A&amp;B🕊<img src="$iconUrl" alt="ball">宝可梦</p>');
    expect((tokens[0] as TagLabelText).text, 'A&B🕊');
    expect((tokens[1] as TagLabelImage).url, iconUrl);
    expect((tokens[1] as TagLabelImage).alt, 'ball');
    expect((tokens[2] as TagLabelText).text, '宝可梦');
  });

  test('supports plain text and malformed HTML without changing search data',
      () {
    expect((TagRichLabelParser.parse('  萌单✏️  ').single as TagLabelText).text,
        '萌单✏️');
    expect(
        (TagRichLabelParser.parse('<p>A<img src="$iconUrl">B').last
                as TagLabelText)
            .text,
        'B');
    expect(TagRichLabelParser.parse(null), isEmpty);
    expect(TagRichLabelParser.parse(''), isEmpty);
    expect(TagRichLabelParser.parse('<p> </p>'), isEmpty);
    expect(TagRichLabelParser.parse('<img>'), isEmpty);
  });

  test('rejects unsafe schemes, credentials, ports and unrecognized hosts', () {
    for (final url in [
      'http://raw.githubusercontent.com/a',
      'javascript:alert(1)',
      'data:image/png;base64,AA',
      'file:///private/test.png',
      '//raw.githubusercontent.com/a',
      'https://127.0.0.1/a',
      'https://raw.githubusercontent.com.evil.example/a',
      'https://user:secret@raw.githubusercontent.com/a',
      'https://raw.githubusercontent.com:444/a',
      'https://[bad',
    ]) {
      expect(TagRichLabelParser.safeImageUrl(url), isNull, reason: url);
      expect(
          TagRichLabelParser.parse('<p><img src="$url">文字</p>')
              .whereType<TagLabelImage>(),
          isEmpty);
    }
  });

  test('ignores script, styles and navigation; decodes URL entities', () {
    final tokens = TagRichLabelParser.parse(
        '<script>bad</script><style>bad</style>'
        '<a href="javascript:bad">文字</a><img src="$iconUrl?a=1&amp;b=2" onclick="bad" width="9999">');
    expect((tokens.first as TagLabelText).text, '文字');
    expect((tokens.last as TagLabelImage).url, '$iconUrl?a=1&b=2');
  });

  test('resource limits and bounded cache do not lose newly parsed labels', () {
    expect(TagRichLabelParser.parse('x' * 8193), isEmpty);
    expect(
        TagRichLabelParser.parse('<img src="$iconUrl">' * 20)
            .whereType<TagLabelImage>()
            .length,
        4);
    final first = TagRichLabelParser.parse('<p>cached</p>');
    expect(identical(first, TagRichLabelParser.parse('<p>cached</p>')), isTrue);
    for (int i = 0; i < TagRichLabelParser.cacheCapacity + 1; i++) {
      TagRichLabelParser.parse('<p>$i</p>');
    }
    expect(
        identical(first, TagRichLabelParser.parse('<p>cached</p>')), isFalse);
    expect(
        () => first.add(const TagLabelText('mutate')), throwsUnsupportedError);
  });
}
