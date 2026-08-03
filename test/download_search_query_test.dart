import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/pages/download_search/download_search_query.dart';
import 'package:jhentai/src/pages/download_search/download_search_state.dart';

void main() {
  group('simple download search', () {
    test('keeps a query without operators as one literal phrase', () {
      expect(
        matchesDownloadSimpleQuery(
          fields: ['foo', 'bar', 'a foo bar title'],
          query: 'foo bar',
          caseSensitive: true,
        ),
        isTrue,
      );
      expect(
        matchesDownloadSimpleQuery(
          fields: ['foo', 'bar'],
          query: 'foo bar',
          caseSensitive: true,
        ),
        isFalse,
      );
    });

    test('applies case sensitivity to literal queries', () {
      expect(
        matchesDownloadSimpleQuery(
            fields: ['Tomboy'], query: 'tomboy', caseSensitive: true),
        isFalse,
      );
      expect(
        matchesDownloadSimpleQuery(
            fields: ['Tomboy'], query: 'tomboy', caseSensitive: false),
        isTrue,
      );
    });

    test('supports AND across fields', () {
      expect(
        matchesDownloadSimpleQuery(
          fields: ['female:tomboy', 'female:stockings'],
          query: '+tomboy +stockings',
          caseSensitive: true,
        ),
        isTrue,
      );
    });

    test('supports OR alternatives', () {
      expect(
        matchesDownloadSimpleQuery(
            fields: ['female:stockings'],
            query: 'tomboy|stockings',
            caseSensitive: true),
        isTrue,
      );
      expect(
        matchesDownloadSimpleQuery(
            fields: ['female:glasses'],
            query: 'tomboy|stockings',
            caseSensitive: true),
        isFalse,
      );
    });

    test('supports NOT alternatives', () {
      expect(
        matchesDownloadSimpleQuery(
            fields: ['tomboy', 'glasses'],
            query: '+tomboy -stockings|pantyhose',
            caseSensitive: true),
        isTrue,
      );
      expect(
        matchesDownloadSimpleQuery(
            fields: ['tomboy', 'pantyhose'],
            query: '+tomboy -stockings|pantyhose',
            caseSensitive: true),
        isFalse,
      );
    });

    test('strips a prefix from an entire OR group', () {
      expect(
        matchesDownloadSimpleQuery(
            fields: ['A', 'B'], query: '+A +B|C -D', caseSensitive: true),
        isTrue,
      );
      expect(
        matchesDownloadSimpleQuery(
            fields: ['A', 'C', 'D'], query: '+A +B|C -D', caseSensitive: true),
        isFalse,
      );
    });

    test('ignores empty operands', () {
      expect(
        matchesDownloadSimpleQuery(
            fields: ['A'], query: '+ | +A ||', caseSensitive: true),
        isTrue,
      );
    });
  });

  group('regex download search', () {
    test('matches across fields and line breaks', () {
      RegExp regExp = buildDownloadSearchRegExp(
          query: r'(?=.*tomboy)(?=.*stockings)', caseSensitive: true);
      expect(regExp.hasMatch('female:tomboy\nfemale:stockings'), isTrue);
    });

    test('applies case sensitivity', () {
      expect(
          buildDownloadSearchRegExp(query: 'tomboy', caseSensitive: true)
              .hasMatch('Tomboy'),
          isFalse);
      expect(
          buildDownloadSearchRegExp(query: 'tomboy', caseSensitive: false)
              .hasMatch('Tomboy'),
          isTrue);
    });

    test('keeps standard unanchored regex behavior', () {
      expect(
          buildDownloadSearchRegExp(query: 'tomboy', caseSensitive: true)
              .hasMatch('prefix tomboy'),
          isTrue);
    });

    test('throws for an invalid expression', () {
      expect(() => buildDownloadSearchRegExp(query: '[', caseSensitive: true),
          throwsFormatException);
    });
  });

  test('falls back to simple search for an invalid persisted type', () {
    expect(DownloadSearchConfigTypeEnum.fromCode(999), DownloadSearchConfigTypeEnum.simple);
  });
}
