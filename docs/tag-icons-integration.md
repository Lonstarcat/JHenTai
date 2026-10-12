# EhSyringe-style tag icons in JHenTai

## Scope and design

Reuse the HTML `fullTagName` already stored from EhTagTranslation's `db.html.json`.
No browser extension code, database migration, new dependency, search/API changes,
or replacement of existing `tagName` values is required.

1. `TagRichLabelParser` converts a bounded HTML fragment to immutable text/image
   tokens, preserving text/Emoji/entity order. Scripts, styling and link actions
   are not executed. Parsed labels use a 256-entry LRU cache.
2. `EHTagLabel` renders tokens using native text and inline image widgets. Icons
   are limited to 16 px (12 px in waterfall lists), with 64 px decoded images,
   existing ExtendedImage caching, a 15-second loading display deadline and no automatic retry.
   Loading/failed images do not replace adjacent tag text.
   The display deadline affects loading decoration only; the image provider remains
   mounted, so a later successful response can still display its icon.
3. Only gallery detail/list/waterfall surfaces opt in. Search history and
   autocomplete remain unchanged. The existing tag owns gestures, vote suffixes,
   delete affordances, colors and status underline.
4. Appearance settings include a persisted **Show tag image icons** switch,
   default off. Turning it off restores original text including Emoji; it does
   not change the database or tag introduction panel.

## Security and compatibility

The image-host allowlist was sampled from the public translation database on
2026-10-11. Initial image URLs require HTTPS, a known host, no credentials and no
non-standard port. HTML dimensions, handlers and styles are ignored. No EH
cookies/authentication headers are attached to icon requests. New/unrecognized
hosts and HTTP-only icons are omitted; ordinary label text remains available.
This validates initial URLs only: redirects use the existing image client's
behavior, without a new per-hop host policy.
The display deadline does not force-abort the existing image library's shared
HTTP connection; underlying IO timeout remains subject to that library/client.

Images are downloaded from external sites when enabled. Network failures,
unsupported formats and future host changes can leave
some tags text-only. This is not a full port of EhSyringe's site translation,
search suggestions or tag introduction implementation.

## Verification

- Parser fixtures: text/entities/Emoji, DOM order, malformed HTML, unsafe URLs,
  skipped executable elements, resource limits and cache eviction.
- Widget fixtures: switch, bounds, failure fallback, vote suffixes, narrow
  waterfall layout and unchanged mouse/touch gestures.
- JSON preference compatibility: missing/invalid key defaults off; round-trip.
- Screenshot report (2026-10-11): the user confirmed the opt-in was not enabled.
  The four actual translation entries (pokemon/azur lane/genshin impact/blue archive)
  retain their image tokens; downloaded WebP/JPEG/JPEG/ICO all decode in Flutter.
  A separate slow-host regression was fixed: the old five-second UI deadline
  disposed the provider and prevented late responses from appearing. A controlled
  production HTTP-provider test now returns real WebP bytes after the new display
  deadline and verifies successful decoding/rendering, without sending credentials.
- Run the full Flutter tests/analyzer, then release builds for macOS and Android
  arm64 using `lib/src/main.dart`.

## Manual testing

Enable Chinese tag translation and refresh its database if necessary. Under
Settings → Appearance, turn on tag image icons. Compare `parody:pokemon` or
`parody:touhou project` with Emoji tags such as `parody:air`. Check detail/list/
waterfall modes, right click/long press, search by tag, light/dark themes and
offline fallback. Turn the switch off and restart to verify persistence.
