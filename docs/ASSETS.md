# Assets & Licensing

## Sticker artwork (`assets/stickers/`)

All sticker SVGs under `assets/stickers/` are **original artwork created specifically
for this project**. They are simple, flat, hand-authored vector illustrations. They do
**not** copy, trace, or embed any existing copyrighted artwork, logos, brand assets, or
third-party icons.

These stickers are released under **CC0 1.0 Universal (Public Domain Dedication)**.
To the extent possible under law, the authors have waived all copyright and related
rights. You are free to copy, modify, distribute, and use them for any purpose,
commercial or non-commercial, without asking permission or giving attribution.

Full license text: https://creativecommons.org/publicdomain/zero/1.0/

### Format notes

- Each sticker is a plain SVG with `viewBox="0 0 100 100"` and **no** fixed `width`/`height`,
  so it scales cleanly to any size in Flutter.
- Flat solid fills and simple strokes only. No embedded raster images, no external
  references, no fonts or `<text>` elements.

### Categories

| Category | Folder | Stickers |
|----------|--------|----------|
| Tape | `assets/stickers/tape/` | washi / adhesive tape strips (`tape_1`–`tape_4`) |
| Love | `assets/stickers/love/` | `heart_solid`, `heart_outline`, `arrow_heart`, `lips` |
| Notes | `assets/stickers/notes/` | `note_sticky`, `pin`, `paperclip`, `star_note` |
| Birthday | `assets/stickers/birthday/` | `cake`, `balloon`, `gift`, `party_hat`, `confetti` |
| Paint | `assets/stickers/paint/` | `brush_stroke`, `splatter`, `drip`, `blob` |
| Frame | `assets/stickers/frame/` | `frame_square`, `frame_rounded`, `frame_polaroid`, `corner` (decorative photo frames with a transparent center) |
| Christmas | `assets/stickers/christmas/` | `tree`, `snowman`, `bauble`, `candy_cane`, `santa_hat` |
| New Year | `assets/stickers/newyear/` | `firework`, `champagne`, `star_burst`, `clock` |
| Winter | `assets/stickers/winter/` | `snowflake`, `mitten`, `snow_pile`, `cloud_snow` |

## Background patterns

The app's decorative **background patterns are rendered programmatically** (drawn in
code at runtime) and are **not** shipped as asset files. There is nothing to license or
attribute for them.

## Emoji

Any emoji shown in the app are rendered by the **operating system's native emoji font**.
They are provided by the platform (iOS, Android, etc.) and are not bundled as assets in
this repository.
