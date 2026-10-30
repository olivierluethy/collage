# Privacy Policy

_Last updated: 30 October 2026_

Collage is a photo collage maker. It is built so that your photos stay on your
device. This page explains what the app accesses, what (if anything) leaves your
device, and why.

## What the app accesses on your device

- **Your photo library** (`READ_MEDIA_IMAGES`), so you can pick photos for a
  collage. Photos are read on your device and are not uploaded anywhere unless
  you use the optional AI feature described below.
- **Photo location metadata** (`ACCESS_MEDIA_LOCATION`), used only by the
  Discover tab to group photos by place and day.
- **Saving to your gallery**, so finished collages can be stored as images.

Collages you save in "My Collages" are stored in the app's private storage on
your device. Deleted collages stay in the app's trash for 30 days. Uninstalling
the app deletes all of them. Images you saved to your gallery stay there.

**Backups.** If you create a backup, the app writes one .zip file with your
collages and the photos they use, and hands it to the Android share sheet.
Where it goes (Google Drive, email, a computer, …) is your choice; the app
itself does not upload it anywhere. Restoring a backup may add its photos back
to your gallery.

## What can leave your device

The app has no account, no advertising and no analytics. Network requests only
happen for the following features:

| Feature | What is sent | Sent to |
|---|---|---|
| Discover (place names) | The coordinates stored in your photos, to turn them into a place name | Your phone's built-in geocoding service (on Android usually Google) |
| AI auto-collage (optional, only when you start it) | Downscaled copies of the photos you selected, plus their date and approximate place | Anthropic's Claude API, directly or through the app publisher's proxy server |
| GIF search (only in builds with a Giphy key) | Your search words | Giphy |
| Extra fonts and stickers (only in builds with a remote catalog) | A request for the catalog and the font/sticker files | The catalog server configured by the app publisher |

Nothing else is transmitted. The AI feature only runs when you choose photos
for it and start it; photos sent to it are used to suggest collage groupings
and are handled under Anthropic's commercial data policies.

## Your choices

- You can use every collage feature without the AI feature.
- You can revoke photo access at any time in Android Settings → Apps → Collage
  → Permissions.
- You can delete saved collages in "My Collages" (long-press a collage).

## Children

The app is not directed at children under 13 and does not knowingly collect
any personal data from them.

## Changes and contact

If this policy changes, the new version will be published at this address with
a new date. Questions: open an issue at
https://github.com/olivierluethy/collage/issues.
