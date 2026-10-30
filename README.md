<div align="center">
  <img src="assets/icon/icon.png" alt="Collage logo" width="140" />
  <h1>Collage</h1>
  <p><b>A photo collage maker where you place every photo yourself.</b><br/>A free Android app that puts you in control of every slot — no autofill.</p>
  <p>
    <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
    <img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white">
    <img alt="Dart" src="https://img.shields.io/badge/Dart-0175C2?logo=dart&logoColor=white">
    <img alt="Riverpod" src="https://img.shields.io/badge/Riverpod-2C6BED?logo=flutter&logoColor=white">
    <img alt="Android" src="https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white">
  </p>
</div>

---

A free photo collage maker for Android where **you** decide which photo goes in which slot. Unlike PicCollage-style apps that autofill for you, Collage puts you in control of every placement.

## Features

- Manual slot assignment with drag-to-swap between slots
- Frame each photo in its slot: drag to reposition, pinch to zoom, twist or tap Rotate to tilt, double-tap to recentre
- Give any photo its own frame and drop shadow, a scrapbook style (Polaroid, tape, torn paper) or a shape (circle, heart, star, …)
- Drag the edges between photos to resize cells right in the editor
- Centre faces automatically and cut a subject out as a sticker (on-device, Google ML Kit)
- Videos in cells (muted, looped) and MP4 export of video collages
- Undo and redo for every edit
- Curated and custom layout templates, each labelled with its aspect-ratio numbers
- 1,000+ ready-made templates, filtered by photo count and style — drop in your photos and post
- Freeform canvas: move, scale, and rotate every element, with snap-to-centre alignment guides
- Layers panel: restack, select, duplicate or delete any element
- Crop free-floating photos
- Stickers across 9 categories, plus optional stickers from your own remote catalog
- Shapes, text (with outline, shadow, letter spacing, curved baseline and colour gradient), and emoji
- Freehand drawing
- One-tap date & place caption from the photos, and AI title ideas
- Optional extra fonts from your own remote catalog (see [docs/CATALOGS.md](docs/CATALOGS.md))
- Optional Giphy GIF search (shown only in builds with a Giphy key)
- Backgrounds: solid, gradient, pattern, or image (with blur)
- Filters: presets including Auto, brightness, contrast, warmth, saturation and vignette
- Live border and spacing controls
- Export as PNG or JPG in three sizes (1080, 2048 or 4096 px), or as an animated GIF when the collage has GIF stickers
- Instagram carousels: 2:1 and 3:1 canvases that save or share as separate square slides
- Instagram profile grids: split a collage into 3×N tiles, numbered in posting order
- Print: A4 canvases and PDF export; photo books that export several collages as one PDF
- Re-editable saved collages in "My Collages" — rename, duplicate or delete with a long-press
- Trash: deleted collages can be restored for 30 days
- Save any design as your own template
- Back up all collages (including their photos) to a .zip and restore them on any phone
- Send a single collage as a file for someone else to edit and send back
- AI auto-collage suggestions
- First-run onboarding that goes straight into your first collage, and a short guided tour of the editor
- Your work is never lost: leaving the editor saves the collage to "My Collages" automatically
- Light and dark themes
- 15 languages
- More tab: photo books, trash, backup, language, theme, tips, About, Privacy Policy and Terms of Service

## Install the APK on Android

1. Open the [GitHub Releases page](../../releases) and download the latest `app-release.apk`. If you prefer a smaller download, grab the ABI-specific file that matches your phone instead. `arm64-v8a` fits most modern phones.
2. On your phone, open the downloaded file.
3. When prompted, allow "Install unknown apps" for the browser or file manager you used to download it.
4. Finish the install, then open Collage.

## Giphy GIF search (optional)

GIF search is powered by the Giphy API. Without a key the GIF tool is simply not shown and the rest of the app works normally.

To enable it:

1. Get a free API key at [developers.giphy.com](https://developers.giphy.com).
2. Build or run with the key passed in:

   ```
   flutter run --dart-define=GIPHY_API_KEY=your_key
   ```

   For release builds, set the `GIPHY_API_KEY` GitHub secret instead.

Never commit a real key to the repository.

## AI auto-collage (optional)

The AI suggestion feature talks to Claude. For release builds, run a small
proxy that holds your Anthropic API key and point the app at it — a key
compiled into an APK can be extracted by anyone:

```
flutter build apk --release --dart-define=AI_PROXY_URL=https://your.site/collage-ai
```

For release builds set the `AI_PROXY_URL` GitHub secret. A ready-to-deploy
Cloudflare Worker is in [proxy/](proxy/README.md); the contract is in
[docs/AI_PROXY.md](docs/AI_PROXY.md).

For local development only, you can call the API directly instead:

```
flutter run --dart-define=AI_API_KEY=your_key
```

Without either, the feature shows a clear message and everything else —
including making collages by hand — works fully.

## More tab (library, backup, settings, legal)

The **More** tab on the home screen groups photo books and the trash, backup and restore, language, theme (light/dark/system), "Show tips again", About, Privacy Policy and Terms of Service. The app ships with 15 languages (English, 中文, हिन्दी, Español, العربية, বাংলা, Français, Русский, Português, Bahasa Indonesia, Deutsch, 日本語, Türkçe, Italiano, 한국어).

Privacy Policy and Terms of Service open in the device browser. By default they
point at [docs/PRIVACY.md](docs/PRIVACY.md) and [docs/TERMS.md](docs/TERMS.md) in
this repository. To use your own pages instead:

```
flutter run --dart-define=PRIVACY_POLICY_URL=https://your.site/privacy \
            --dart-define=TERMS_URL=https://your.site/terms
```

For release builds use the `PRIVACY_POLICY_URL` and `TERMS_URL` GitHub secrets.

## Templates

The **Templates** tab holds 1,000+ ready-made designs, generated by combining a
layout, a colour look, a border treatment and a decoration set (text, stickers,
shapes). Filter them two ways:

- **Photos** — the number of photos a design is built for (1–9).
- **Style** — Minimal, Birthday, Love, Travel, Party, Family, Summer, Winter,
  Social or Aesthetic.

Each design comes in square (Instagram feed), portrait (Facebook feed) and story
(Instagram / Snapchat) shapes. Tapping a tile opens the editor with the styling
already applied and empty slots — add your photos with the **Photos** tool and
the design fills itself in, ready to save and post.

## Custom fonts & stickers (optional)

Extra fonts and stickers can be loaded at runtime from your own JSON catalogs —
no code changes needed. Supply the URLs at build time:

```
flutter run \
  --dart-define=FONT_CATALOG_URL=https://your.site/collage/fonts.json \
  --dart-define=STICKER_CATALOG_URL=https://your.site/collage/stickers.json
```

For release builds set the `FONT_CATALOG_URL` and `STICKER_CATALOG_URL` GitHub
secrets. Both are optional — without them the bundled fonts and stickers are
used. See [docs/CATALOGS.md](docs/CATALOGS.md) for the catalog JSON format.

## Build it yourself

```
flutter pub get
flutter build apk --release
```

The `--dart-define=GIPHY_API_KEY=...` and `--dart-define=AI_PROXY_URL=...` flags are optional; add them if you want GIF search and AI suggestions enabled in your build.

Release builds are signed with the keystore stored in the `ANDROID_KEYSTORE_*`
GitHub secrets. A local `flutter build apk --release` without
`android/key.properties` is signed with the debug key instead, so it cannot be
installed over a release build (or the other way round) without uninstalling
first.

## Releasing

Maintainers publish a new version by pushing a git tag:

```
git tag v1.0.0
git push origin v1.0.0
```

This triggers the GitHub Actions workflow that builds the APKs and publishes a GitHub Release with them attached.

## Tech

Flutter, Riverpod, photo_manager, permission_handler.

## License

The code is licensed under the [MIT License](LICENSE) © 2026 Olivier Lüthy. You're free to use, modify and distribute this software, including commercially, as long as the copyright notice and license are included. Bundled sticker assets are released under CC0 — see [docs/ASSETS.md](docs/ASSETS.md) for details. For the design system, see [docs/STYLEGUIDE.md](docs/STYLEGUIDE.md).

## Author

Built by **Olivier Lüthy** — [GitHub](https://github.com/olivierluethy).
