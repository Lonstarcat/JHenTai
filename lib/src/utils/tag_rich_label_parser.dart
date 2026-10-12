import 'dart:collection';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

sealed class TagLabelToken {
  const TagLabelToken();
}

class TagLabelText extends TagLabelToken {
  final String text;
  const TagLabelText(this.text);
}

class TagLabelImage extends TagLabelToken {
  final String url;
  final String alt;
  const TagLabelImage(this.url, this.alt);
}

/// Display-only parsing. Never use these tokens to construct search/API keys.
/// Hosts sampled from EhTagTranslation db.html.json on 2026-10-11.
class TagRichLabelParser {
  static const int cacheCapacity = 256;
  static const Set<String> _imageHosts = {
    'raw.githubusercontent.com',
    'user-images.githubusercontent.com',
    'media.9game.cn',
    'p.sda1.dev',
    'aigis1000.jp',
    'lain.bgm.tv',
    'cdnimg01.gamekee.com',
    'cdnimg-v2.gamekee.com',
    'image.tvsou.com',
    'www.nijisanji.jp',
    'bluearchive.nexon.com',
    'hololive.hololivepro.com',
    'zenless.hoyoverse.com',
    'heaven-burns-red.com',
    'hsr.hoyoverse.com',
    'novaweb-static.stargazer-games.com',
    'static.wikia.nocookie.net',
    'patchwiki.biligame.com',
    'typemoon.com',
    'thumbsnap.com',
    'i.pixiv.cat',
  };
  static final LinkedHashMap<String, List<TagLabelToken>> _cache = LinkedHashMap();

  static String? safeImageUrl(String? source) {
    if (source == null || source.length > 2048 || source.contains(r'\')) {
      return null;
    }
    final Uri? uri = Uri.tryParse(source.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !_imageHosts.contains(uri.host.toLowerCase())) {
      return null;
    }
    return uri.toString();
  }

  static List<TagLabelToken> parse(String? source) {
    if (source == null || source.trim().isEmpty || source.length > 8192) {
      return const [];
    }
    final List<TagLabelToken>? cached = _cache.remove(source);
    if (cached != null) {
      _cache[source] = cached;
      return cached;
    }
    final List<TagLabelToken> tokens = [];
    int images = 0;
    void visit(dom.Node node) {
      if (tokens.length >= 64) {
        return;
      }
      if (node is dom.Text) {
        final String text = node.data.replaceAll(RegExp(r'\s+'), ' ');
        if (text.isNotEmpty) {
          tokens.add(TagLabelText(text));
        }
      } else if (node is dom.Element) {
        if (const {'script', 'style', 'iframe', 'object', 'embed', 'template', 'svg', 'link'}.contains(node.localName)) {
          return;
        }
        if (node.localName == 'img') {
          final String? url = safeImageUrl(node.attributes['src']);
          // Do not let arbitrary HTML create executable widgets or image requests.
          if (url != null && images < 4) {
            tokens.add(TagLabelImage(url, node.attributes['alt'] ?? ''));
            images++;
          }
          return;
        }
        if (node.localName == 'br') {
          tokens.add(const TagLabelText(' '));
        }
        for (final dom.Node child in node.nodes) {
          visit(child);
        }
      }
    }

    for (final dom.Node node in html.parseFragment(source).nodes) {
      visit(node);
    }
    // HTML wrappers and indentation must not introduce leading/trailing spaces.
    if (tokens.isNotEmpty && tokens.first is TagLabelText) {
      tokens[0] = TagLabelText((tokens.first as TagLabelText).text.trimLeft());
    }
    if (tokens.isNotEmpty && tokens.last is TagLabelText) {
      tokens[tokens.length - 1] = TagLabelText((tokens.last as TagLabelText).text.trimRight());
    }
    tokens.removeWhere((token) => token is TagLabelText && token.text.isEmpty);
    final List<TagLabelToken> result = List.unmodifiable(tokens);
    _cache[source] = result;
    if (_cache.length > cacheCapacity) {
      _cache.remove(_cache.keys.first);
    }
    return result;
  }
}
