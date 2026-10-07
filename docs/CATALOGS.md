# Fonts & sticker catalogs (remote)

The app ships with a small curated set of fonts and stickers. You can extend
both **at runtime from a URL** — nothing is hard-coded. Point the app at a JSON
catalog; it is fetched once, cached on the device for offline use, and merged on
top of the bundled sets. If a URL is empty or the fetch fails, the bundled sets
keep working — the app never depends on the catalogs.

## Supplying the URLs

Pass them at build time (they default to empty):

```
flutter run \
  --dart-define=FONT_CATALOG_URL=https://your.site/collage/fonts.json \
  --dart-define=STICKER_CATALOG_URL=https://your.site/collage/stickers.json
```

For release builds set the `FONT_CATALOG_URL` and `STICKER_CATALOG_URL` GitHub
secrets; the release workflow already forwards them.

## Font catalog format

```json
{
  "fonts": [
    { "key": "bangers",  "family": "Bangers", "googleFont": "Bangers" },
    { "key": "my-font",  "family": "My Font", "url": "https://your.site/fonts/MyFont-Regular.ttf" }
  ]
}
```

- `key` — stable id stored with the text element. Optional; defaults to `family`.
- `family` — the name shown in the text panel.
- `googleFont` — a [Google Fonts](https://fonts.google.com) family name
  (case-sensitive). Loaded on demand over the network by `google_fonts`.
- `url` — a direct TrueType/OpenType file. It is downloaded once at startup and
  registered with the engine; a broken URL simply falls back to the default font.

An entry may use `googleFont` **or** `url` (not both). Unknown Google families
fall back to Inter.

## Sticker catalog format

```json
{
  "categories": [
    {
      "id": "emoji",
      "label": "Emoji",
      "stickers": [
        { "name": "smile", "url": "https://your.site/stickers/smile.svg" },
        { "name": "wink",  "url": "https://your.site/stickers/wink.png" }
      ]
    }
  ]
}
```

- Each category becomes its own tab in the Stickers panel, after the bundled
  categories.
- `url` may point at an SVG (rendered with `flutter_svg`) or a raster image
  (png / webp / jpg / gif). The extension decides the renderer.

## Caching & privacy

The raw JSON is cached in `SharedPreferences`, so the catalogs are available
offline after the first successful fetch. Only the catalog URLs you configure are
requested; nothing else is uploaded.
