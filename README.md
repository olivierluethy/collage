<div align="center">
  <img src="assets/icon/ic_launcher.png" alt="Collage app icon: three photos arranged as a collage" width="140" />
  <h1>Collage</h1>
  <p><b>A photo collage maker where you place every photo yourself.</b><br/>A free Android app that puts you in control of every slot — no autofill.</p>
  <p>
    <img alt="Version 1.6.0" src="https://img.shields.io/badge/version-1.6.0-FFB454">
    <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
    <img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white">
    <img alt="Dart" src="https://img.shields.io/badge/Dart-0175C2?logo=dart&logoColor=white">
    <img alt="Riverpod" src="https://img.shields.io/badge/Riverpod-2C6BED?logo=flutter&logoColor=white">
    <img alt="Android" src="https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white">
  </p>
</div>

---

A free photo collage maker for Android where **you** decide which photo goes in which slot. Unlike PicCollage-style apps that autofill for you, Collage puts you in control of every placement.

## How it works

1. **Pick photos.** Tap *New collage* → *Pick photos* and choose up to 9. The order you tap fills the slots.
2. **Arrange them.** You land straight in the editor with a layout that fits your photo count. Drag a photo onto another to swap them, or change the layout and shape (square, story, A4, …) with the **Layout** tool.
3. **Make it yours, then save.** Add text, stickers and more, then tap **Finish** → *Save to gallery* and share it.

Leaving the editor keeps your collage in **My Collages** automatically, so you can come back and edit it any time. You can also start from a ready-made template instead of an empty layout.

## What's new in 1.6

- **Simpler start:** onboarding shows what the app makes and goes straight into your first collage. The language can be changed on the very first screen.
- **Four tabs:** Collages · Templates · Discover · More. One *New collage* button with three ways in: pick photos, start from a template, or an AI suggestion.
- **Fewer steps:** after picking photos you're in the editor right away. Layout and canvas shape are changed in place.
- **Tidier editor:** five tools instead of twelve: Photos · Layout · Style (borders, background, filters) · Add (text, stickers, emoji, shapes, GIFs, drawing) · Layers. A short guided tour on first use.
- **Nothing gets lost:** auto-save when you leave the editor or switch apps. Deleting a collage offers *Undo*, and deleting forever always asks first.
- **Faster saving:** *Save to gallery* saves immediately. The result screen leads with *Share* and groups the Instagram grid and carousel exports.

## Features

**Placing photos**
- Manual slot assignment with drag-to-swap between slots
- Frame each photo in its slot: drag to reposition, pinch to zoom, twist or tap Rotate to tilt, double-tap to recentre
- Drag the edges between photos to resize cells right in the editor
- Centre faces automatically and cut a subject out as a sticker (on-device, Google ML Kit)
- Videos in cells (muted, looped) and MP4 export of video collages

**Layouts & templates**
- Curated layouts for 1–9 photos, including diagonal and mosaic cells, or build your own
- Canvas shapes with names and numbers: Square 1:1, Portrait 4:5, Story 9:16, Landscape, Wide, Instagram carousels (2:1, 3:1) and A4 print
- 1,000+ ready-made templates, filtered by photo count and style — drop in your photos and post
- Save any design as your own template

**Styling & decoration**
- Give any photo its own frame and drop shadow, a scrapbook style (Polaroid, tape, torn paper) or a shape (circle, heart, star, …)
- Backgrounds: solid, gradient, pattern, or image (with blur)
- Filters: presets including Auto, brightness, contrast, warmth, saturation and vignette, for the whole collage or a single photo
- Live border and spacing controls
- Text with outline, shadow, letter spacing, curved baseline and colour gradient
- Stickers across 9 categories, emoji, shapes and freehand drawing
- One-tap date & place caption from the photos, and AI title ideas
- Optional Giphy GIF search, extra fonts and stickers from your own remote catalogs

**Editing**
- Freeform canvas: move, scale and rotate every element, with snap-to-centre alignment guides
- Layers panel: restack, select, duplicate or delete any element
- Crop, flip and straighten free-floating photos
- Undo and redo for every edit

**Saving & sharing**
- Export as PNG or JPG in three sizes (1080, 2048 or 4096 px), as an animated GIF when the collage has GIF stickers, as MP4 for video collages, or as PDF
- Instagram carousels that save or share as separate square slides
- Instagram profile grids: split a collage into 3×N tiles, numbered in posting order
- Photo books that export several collages as one printable PDF
- Send a single collage as a file for someone else to edit and send back

**Your library**
- Re-editable collages in "My Collages", saved automatically — open, rename, duplicate, send or delete from the ⋯ menu
- Trash: deleted collages can be restored for 30 days
- Back up all collages (including their photos) to a .zip and restore them on any phone
- AI auto-collage suggestions and Discover moments by place and date

**Comfort**
- Guided first start and a short editor tour, replayable any time
- Light and dark themes, 15 languages
- Large touch targets, screen-reader labels and support for larger text

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

Without either, the AI suggestion is simply not offered in the *New collage*
sheet, and everything else — including making collages by hand — works fully.

## More tab (library, backup, settings, legal)

The **More** tab on the home screen groups everything that isn't making a collage:

- **Library** — photo books and the trash (with a count of what's in it)
- **Backup** — back up all collages to a file, restore a backup, or import a collage someone sent you
- **Settings** — language, theme (light/dark/system) and "Show tips again"
- **About** — app info and version, Privacy Policy and Terms of Service

 The app ships with 15 languages (English, 中文, हिन्दी, Español, العربية, বাংলা, Français, Русский, Português, Bahasa Indonesia, Deutsch, 日本語, Türkçe, Italiano, 한국어).

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
the design fills itself in, ready to save and post. You can also get here from
*New collage* → *Start from a template*.

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
flutter build apk --release                 # one universal APK
flutter build apk --release --split-per-abi # smaller APKs per CPU type
```

The `--dart-define=GIPHY_API_KEY=...` and `--dart-define=AI_PROXY_URL=...` flags are optional; add them if you want GIF search and AI suggestions enabled in your build.

To update the app on a phone connected by USB without losing its collages, install over the existing app:

```
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Split APKs get a version code of `<ABI offset> + build number` (arm64: 2000 + build), so a
universal APK can't be installed over a split one — stick to one kind per phone.

Release builds are signed with the keystore stored in the `ANDROID_KEYSTORE_*`
GitHub secrets. A local `flutter build apk --release` without
`android/key.properties` is signed with the debug key instead, so it cannot be
installed over a release build (or the other way round) without uninstalling
first.

## Releasing

Maintainers publish a new version by pushing a git tag:

```
git tag v1.6.0
git push origin v1.6.0
```

This triggers the GitHub Actions workflow that builds the APKs and publishes a GitHub Release with them attached.

## Tech

- **Flutter** & **Dart**, state with **Riverpod**
- Gallery & permissions: photo_manager, permission_handler
- On-device vision: Google ML Kit (face detection, subject segmentation)
- Media & export: image, pdf, video_player, archive (backups), share_plus
- Type: google_fonts (Fraunces, Inter, JetBrains Mono) — the "Darkroom" design system is documented in [docs/STYLEGUIDE.md](docs/STYLEGUIDE.md)

## License

The code is licensed under the [MIT License](LICENSE) © 2026 Olivier Lüthy. You're free to use, modify and distribute this software, including commercially, as long as the copyright notice and license are included. Bundled sticker assets are released under CC0 — see [docs/ASSETS.md](docs/ASSETS.md) for details. For the design system, see [docs/STYLEGUIDE.md](docs/STYLEGUIDE.md).

## Author

Built by **Olivier Lüthy** — [GitHub](https://github.com/olivierluethy).
