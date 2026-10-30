# Collage — Style Guide

> **Single source of truth for the app's visual system.** Dark and light themes.
> Every screen, feature, and future change must look like it was always part of this product.
> Colours and text styling stay exactly as defined here. When in doubt, copy a token — never invent one.

The design system lives in Flutter as **design tokens** (`lib/theme/tokens.dart`) mapped into a
Material 3 dark `ThemeData` (`lib/theme/app_theme.dart`). This document is the human-readable
contract those files implement.

---

## 1. Aesthetic thesis — "Darkroom"

A collage is physical photo-craft: prints on a lightbox, tape, photo corners, arranging by hand
under the warm amber **safelight** of a darkroom. The chrome is a warm near-black so the user's
photos are the only real colour on screen (the same reason Lightroom, Procreate and Figma go dark).
This is a deliberate *warm* dark theme — not the cold "near-black + one acid-green accent" default.

**Signature element:** the amber **safelight glow** on the selected/active canvas element, paired
with monospace **spec chips** (`1:1`, `4:5`, `2048×2048`, `3/9`) that expose the numbers a maker
wants to see. Boldness is spent here and nowhere else — everything around it stays quiet.

**Voice:** plain, active, sentence case. Buttons say what happens ("Save to gallery", not "Export").
An action keeps its name through the whole flow. Empty states invite the next move.

---

## 2. Colour tokens

Two palettes share one set of token names (`AppPalette` in `lib/theme/palette.dart`): the warm
near-black **Darkroom** (dark) and the warm off-white **lightbox** (light). Surfaces climb in
lightness with elevation; amber is the single brand accent in both.
Hex values are canonical. Alpha given as `rgba()` or `@NN%`.

Widgets read the live colours with `context.colors.<token>` — never hardcode a hex. The tables below
list the dark values; the light equivalents follow after them.

### Base & surfaces
| Token | Hex | Use |
|---|---|---|
| `ink` / background | `#131110` | App scaffold background, canvas letterbox |
| `inkCanvas` | `#1A1714` | Editor canvas backdrop behind the collage |
| `surface` | `#211D19` | Sheets, cards, toolbars |
| `surfaceHigh` | `#2A2521` | Menus, popovers, elevated cards, selected tab track |
| `surfaceInput` | `#332D28` | Text fields, sliders track, chip (unselected) |
| `line` | `#3D362F` | Hairline borders, dividers (1px) |
| `lineStrong` | `#4E463D` | Emphasised borders, handle rings (1.5px) |

### Text & icons
| Token | Hex | Use |
|---|---|---|
| `textHi` | `#F5EFE7` | Primary text, active icons |
| `textMid` | `#B6AB9D` | Secondary text, inactive labels |
| `textLo` | `#8A7F71` | Hints, captions, placeholder |
| `textDisabled` | `#5E564C` | Disabled text & icons |

### Brand accent — Safelight amber
| Token | Hex | Use |
|---|---|---|
| `amber` / primary | `#FFB454` | Primary buttons, FAB, selection, active state, focus ring |
| `amberPressed` | `#F59E2E` | Pressed/active primary |
| `amberBright` | `#FFC97A` | Glow highlight, subtle top-edge of amber fills |
| `onAmber` | `#2A1B08` | Text/icons on amber fills (dark espresso, high contrast) |
| `amberTint` | `rgba(255,180,84,0.12)` | Selected chip/tab background, tool-active tint |
| `amberGlow` | `rgba(255,180,84,0.32)` | Safelight glow shadow around selection |

### Semantic
| Token | Hex | Use |
|---|---|---|
| `success` | `#6FD08C` | Saved confirmation, valid |
| `danger` | `#FF6B5E` | Destructive (delete, clear), errors — the darkroom red |
| `onDanger` | `#2A0E0B` | Text/icons on danger fills |
| `info` | `#6FB2FF` | Neutral tips, links, non-brand highlights |
| `warning` | `#E7B84B` | Caution (distinct from brand amber by lower chroma) |

**Contrast:** `textHi` on `ink` ≈ 15:1; `onAmber` on `amber` ≈ 8:1; `textMid` on `surface` ≥ 5:1.
Never place `textLo` on anything lighter than `surfaceHigh`.

### Light palette (lightbox)
| Token | Hex | Notes |
|---|---|---|
| `ink` / background | `#F7F3ED` | Warm paper scaffold |
| `inkCanvas` | `#EDE6DC` | Editor canvas backdrop |
| `surface` | `#FFFFFF` | Sheets, cards, toolbars |
| `surfaceHigh` | `#F1EAE0` | Menus, popovers, elevated cards |
| `surfaceInput` | `#E8DFD3` | Text fields, slider track, chip (unselected) |
| `line` | `#DCD1C2` | Hairline borders, dividers |
| `lineStrong` | `#C4B6A3` | Emphasised borders, handle rings |
| `textHi` | `#221C15` | Primary text, active icons |
| `textMid` | `#6A6155` | Secondary text, inactive labels |
| `textLo` | `#8A8174` | Hints, captions, placeholder |
| `textDisabled` | `#B4AA9C` | Disabled text & icons |
| `amber` | `#E08A1E` | Same safelight accent, darkened for contrast on light |
| `amberPressed` | `#C97812` | Pressed/active primary |
| `amberBright` | `#F0AE4E` | Glow highlight |
| `onAmber` | `#2A1B08` | Text/icons on amber fills |
| `success` | `#2E9B57` | Saved confirmation, valid |
| `danger` | `#D63B2F` | Destructive (delete, clear), errors |
| `onDanger` | `#FFFFFF` | Text/icons on danger fills |
| `info` | `#2F6FD0` | Neutral tips, links |
| `warning` | `#B07C0A` | Caution |

---

## 3. Typography

Three roles, three families (bundled via `google_fonts`, cached at build):

| Role | Family | Why |
|---|---|---|
| **Display** | **Fraunces** (600/700, soft, opsz-high) | Warm editorial serif — photo-album personality. Titles, wordmark, empty-state headings. Used with restraint. |
| **UI / Body** | **Inter** (400/500/600) | Maximum legibility for a non-technical user. All controls, labels, body copy. |
| **Spec / Numeric** | **JetBrains Mono** (500) | Technical spec feel for the numbers makers want: aspect ratios, pixel dims, counters. |

### Type scale
| Style | Family / Weight | Size / Line | Tracking | Use |
|---|---|---|---|---|
| `displayLg` | Fraunces 600 | 34 / 1.15 | −0.5 | First-run & empty-state hero |
| `displayMd` | Fraunces 600 | 26 / 1.20 | −0.3 | Screen hero titles |
| `titleLg` | Inter 600 | 22 / 1.25 | 0 | App bar titles, sheet titles |
| `titleMd` | Inter 600 | 18 / 1.30 | 0 | Section headers, dialog titles |
| `bodyLg` | Inter 400 | 16 / 1.50 | 0 | Primary body, rationale copy |
| `bodyMd` | Inter 400 | 14 / 1.45 | 0 | Secondary body, list items |
| `labelLg` | Inter 600 | 15 / 1.20 | 0.1 | Button labels |
| `labelMd` | Inter 600 | 13 / 1.20 | 0.3 | Chips, tabs, small buttons |
| `caption` | Inter 500 | 12 / 1.40 | 0.2 | Hints, coach-marks, counts |
| `overline` | Inter 700 | 11 / 1.20 | 1.2 (UPPER) | Section eyebrows, category labels |
| `spec` | JetBrains Mono 500 | 13 / 1.10 | 0.5 | Ratio chips, dims, `3/9` counters |

Body copy never below 14. Titles use Fraunces only at `displayMd`+ ; smaller headers use Inter 600.

---

## 4. Spacing, radii, layout

**Spacing scale (dp, base-4):** `xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32 · xxxl 48 · huge 64`.
Screen gutter = `lg (16)`. Sheet padding = `xl (24)`. Gap between controls ≥ `sm (8)`.

**Radii:** `chip 6 · control 10 · card 14 · sheet 20 · sheetTop 28 · pill 999`.
Photo-slot corner radius is **user-controlled 0–48**, default **8** (a Borders control, not a token).

**Touch targets:** min **48×48 dp** for any tappable; primary buttons ≥ **56** tall; icon buttons 48.
Two targets never sit closer than `sm (8)`.

**Grid:** single-column mobile-first. Tool sheets are bottom sheets. Editor uses a fixed bottom
tool-rail (scrollable horizontally) + a contextual top bar.

---

## 5. Elevation & the signature glow

Shadows on dark are subtle; lightness of surface does most of the lifting. Focus is shown with amber.

| Token | Value | Use |
|---|---|---|
| `e1` card | `0 1 2 rgba(0,0,0,0.40)` | Cards, chips |
| `e2` sheet | `0 -8 32 rgba(0,0,0,0.50)` | Bottom sheets |
| `e3` menu | `0 12 32 rgba(0,0,0,0.55)` | Popovers, dropdowns, dialogs |
| **`focusGlow`** | `0 0 0 2 amber` **+** `0 0 20 amberGlow` | **Signature.** Selected canvas element, focused field |

The glow is the one place the UI "lights up". Never apply it to more than one element at a time.

---

## 6. Component patterns

**Buttons**
- *Primary* — `amber` fill, `onAmber` text, `labelLg`, radius `control`, height 56, pressed → `amberPressed`.
- *Secondary (tonal)* — `surfaceHigh` fill, `textHi` text, hairline `line` border.
- *Ghost* — transparent, `textMid` text/icon; pressed overlay `white @8%`.
- *Destructive* — `danger` fill, `onDanger` text; or ghost with `danger` text for low-emphasis.
- Disabled — `surfaceHigh` fill, `textDisabled` text, no glow.

**Icon button** — 48×48, `textMid` default, `textHi` active, `amber` when its tool is selected.

**Chips / segmented / tabs** — unselected `surfaceInput` + `textMid`; selected `amberTint` bg + `amber` text/`labelMd`. Layout & ratio chips carry a `spec` sub-label.

**Spec chip (signature)** — pill, `surfaceHigh` bg, `spec` text in `textMid`, e.g. `4:5` · `2048×2048` · `3/9`. On a selected item the number turns `amber`.

**Bottom sheet** — `surface` bg, `sheetTop` radius on top corners, 40×4 `line` grab handle, `titleMd` title, `e2` shadow, drag-to-dismiss. Every tool opens here.

**Bottom tool-rail** — `surface`, horizontal scroll of icon+`labelMd` tools; active tool icon `amber`.

**FAB / primary create** — `amber` pill, `onAmber`, `labelLg`, `e3`. Label always visible ("New collage", "Save").

**Snackbar / toast** — `surfaceHigh`, `bodyMd`, leading status icon (`success`/`danger`), one action in `amber`.

**Coach-mark** — `surfaceHigh` bubble, `amber` hairline border, pointer triangle, `caption`/`titleMd`, "Got it" ghost + optional "Show me". Spotlight dims the rest with `ink @72%`. First one may pulse the `focusGlow` once; respect reduced-motion.

**Selection handles (canvas)** — bounding box `1.5px amber` + `focusGlow`. Corner handles: 22dp `surface` circle, `1.5px amber` ring, amber icon (rotate ⟳ top, scale ⤢ corners, delete × on a `danger` circle top-left). Handles never smaller than 22 and stay on-screen when the element is near an edge.

**Photo slot** — empty: `surfaceInput` fill, dashed `line` border, centred `+` in `textLo` and a `spec` size hint. Filled: image, thin `line` inset. Tap target for assignment covers the whole slot; a small amber `⇄` badge appears on long-press to signal "drag to swap".

---

## 7. Interactive states

| State | Treatment |
|---|---|
| Default | Token base |
| Pressed | Overlay `white @8%` (light controls) or `amberTint` (amber controls) |
| Focused | `focusGlow` (2px amber ring) |
| Selected/Active | `amberTint` bg + `amber` text/icon |
| Disabled | `textDisabled` on `surfaceHigh`, no shadow/glow, 0 elevation |
| Loading | Amber circular indicator on dimmed control; label → present-tense ("Saving…") |
| Error | `danger` border + `danger` `caption` helper below |

---

## 8. Motion

Durations: `fast 120ms · base 200ms · slow 320ms · sheet 280ms`.
Curves: standard `Cubic(0.2, 0, 0, 1)`; emphasised sheet `Cubic(0.05, 0.7, 0.1, 1)`.
Use motion to explain (sheet rise, selection glow, slot-swap tween), not to decorate.
**Respect `MediaQuery.disableAnimations` / reduced-motion**: drop glow pulses and cross-fades, keep instant state changes.

---

## 9. Accessibility floor

- Contrast ≥ 4.5:1 for body, ≥ 3:1 for large text & icons (all tokens above pass).
- Every tappable ≥ 48dp with a semantics label in plain language.
- Never encode meaning by colour alone — pair with icon + text (e.g. delete = `×` + "Delete").
- Honour text scale to at least 1.3× without clipping; controls grow, not truncate.
- Reduced motion respected everywhere.

---

## 9b. Feature patterns (v1.2 additions)

New patterns introduced for creation dates, filters, diagonal layouts and the
picker tray. They reuse existing tokens only — no new colour or font is added.

**Meta line (date/spec)** — a single `caption` row in `textLo` used under a
collage title to carry non-editorial metadata (creation date, counts). Date is
stored as a raw epoch and formatted at display time with `intl`, German-friendly
`dd.MM.yyyy · HH:mm` by default, following the device locale. Pair a small
`schedule`/`event` icon (13dp, `textLo`) with the text; never colour it amber —
metadata stays quiet.

**Filter panel** — same bottom tool-rail entry + shrinking-canvas panel as every
other tool. Header carries a `SegmentedButton` scope toggle: `Whole collage` /
`This photo` (the selected cell). Below it, a horizontal **preset strip**
(56×56 live thumbnails, selected = 2px `amber` ring + `amber` `caption` label,
unselected = `line` hairline), then `LabeledSlider` rows for Brightness /
Contrast / Warmth / Saturation reusing the Borders panel slider pattern (range
shown as a signed `spec` value, 0 = neutral). A ghost "Reset" `TextButton` in the
header clears adjustments. When scope is `This photo` and no cell is selected,
show a `caption` hint "Tap a photo in the collage to filter just that one."
Filters render with `ColorFiltered`/`ColorFilter.matrix` so what's on screen is
exactly what the export bakes.

**Diagonal / polygon cells** — layout slots may be arbitrary polygons, not only
rectangles. A polygon cell clips its photo with `ClipPath` (which also clips the
tap target, so overlapping bounding boxes still hit-test to the right cell).
Gaps are an inward inset toward the cell centroid by `gap/2`; the `Border`
setting strokes the polygon edges in the border colour. Rectangular slots are
unchanged (rounded corners honoured) — polygons are an additive special case, so
no existing straight grid regresses. Miniatures and the layout picker draw the
same polygons so the card preview matches the result.

**Selected-images tray** — a static strip pinned above the picker's primary
button, never scrolling away with the grid. `surface` bg, top `line` hairline,
`e2` shadow. Leading `spec` count chip (`3/9`). Then a horizontal list of 56dp
rounded thumbnails; the active/focused one carries the `amber` ring. Each
thumbnail has a 20dp `×` remove affordance (dark scrim circle, white icon,
top-right). Tapping a thumbnail focuses/scrolls to it in the grid; the `×`
removes it from the selection. Empty selection collapses the tray.

---

## 9c. Flow patterns (v1.6 additions)

The v1.6 overhaul made the app simpler to get around. It reuses existing tokens only and adds no new
colour or font. The rule behind each pattern: show the common path first, keep the rare things one
level down, and never lose work.

**Mini collage (illustration)** — `MiniCollage` (`lib/widgets/mini_collage.dart`). Three drawn
"prints" on a `surface` lightbox (`sheet` radius, `line` border, `e3`). Used in onboarding and the
empty library instead of a lone icon, so the app shows what it makes. With `swap: true` two prints
trade places on a loop and the moving one lifts with the amber ring and glow. This is the one
decorative animation in the app and it stops under reduced motion. The print gradients are
illustration content, not chrome.

**Onboarding** — three pages: *what it makes* → *you decide what goes where* (animated swap) →
*start*. A language chip sits top-left on every page. The last page asks for gallery access in place
(**Pick photos** → straight into the picker) or lets the user **Look around first**. The primary
button keeps the same position on every page.

**Home navigation** — four tabs: Collages · Templates · Discover · More. The app bar carries only
the title (`displayMd`), with no icon clutter. The **New collage** FAB (Collages, Discover) opens the
*New collage sheet*: `ActionCard`s for Pick photos (primary: `amberTint` fill, `amber` border,
`amber` icon tile) · Start from a template · AI suggestion (only when AI is configured: never
offer a dead end).

**Action card** — `ActionCard` in `ui.dart`: min height 72, `card` radius, 44dp icon tile, title in
`labelLg`, one line in `bodyMd`/`textMid`, trailing chevron. For choices that start a flow.

**More tab** — grouped surface cards (`card` radius, `line` border, inset dividers at 56). Group
titles are `labelMd`/`textMid` in sentence case, not overline caps. A row's current value
(language, theme) shows in `amber` under its title; a count (trash) as a `SpecChip`. External links
end in `open_in_new`.

**Cards with menus** — every collage card has a visible ⋯ `IconButton`; long-press stays as a
shortcut. Moving to trash is never confirmed. Instead a snackbar offers **Undo**. Only actions that
can't be undone (delete forever, empty trash, delete template/book) use `confirmDestructive`, whose
danger button names the action.

**Snackbars** — always via `showAppSnack` / `showAppSnackOn`: leading status icon (`success` ✓,
`danger` !, `info` i), one line, at most one amber action. 4s, or 6s with an action.

**Editor** — the back button **auto-saves** the draft (and the app saves on pause). A brief
"Saved to My Collages" toast confirms it. The title in the app bar is tappable to rename. The
primary action is **Finish** → export sheet. Tool rail = five equal, never-scrolling tools:
Photos · Layout · Style · Add · Layers. The active tool gets an `amberTint` pill.
- *Style* = one panel with a `SegmentedButton` Borders / Background / Filter; it reopens on the last tab.
- *Add* = a 3-column grid of `surfaceHigh` tiles (Text, Stickers, Emoji, Shapes, GIF, Draw). The panel
  a tile opens shows a back arrow to the grid.
- *Context bar* = at most four equal actions (Edit/Crop · Duplicate · More · Delete). Flip, order and
  straighten live in the More sheet.

**Coach tour** — `showCoachTour` (`lib/widgets/coach_tour.dart`) implements §6 Coach-mark as a short
sequence: `ink @72%` scrim with a rounded cut-out, `amber` 2px ring + `amberGlow` around the target,
`surfaceHigh` bubble with `amber` hairline, a `spec` step counter (`2/3`), **Skip** + **Next/Got it**.
Tapping anywhere advances. Shown once per tour id, and replayable from the menu or by
More → Show tips again.

**Picker hints** — one-line `_Banner` rows above the grid (`surfaceHigh`, bottom `line`): a one-time
tap-order hint and, under limited access, "Share more". The primary button says what happens next
("Create collage with 3 photos").

**Result** — opening it already saves to the gallery; a live status line reports
saving / saved / failed with **Try again**. Primary = **Share**; secondary = Keep editing · Done.
Instagram grid and carousel exports collapse into one "For Instagram" group.

---

## 10. How to use this file

1. Read a token from the table; use the matching constant in `lib/theme/tokens.dart`.
2. Never hardcode a hex or size in a widget — reference the theme or tokens.
3. New feature? Compose existing components. If a genuinely new pattern is needed, add it here first,
   in this house style, then build it. The app must always look like one product.
