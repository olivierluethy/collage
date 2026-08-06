/// The bundled sticker set, grouped into the categories the brief calls for.
/// Paths match the CC0 SVGs under assets/stickers/ (see docs/ASSETS.md).
class StickerCategory {
  const StickerCategory(this.label, this.dir, this.files);
  final String label;
  final String dir;
  final List<String> files;

  List<String> get assetPaths =>
      files.map((f) => 'assets/stickers/$dir/$f').toList();
}

class StickerCatalog {
  StickerCatalog._();

  static const List<StickerCategory> categories = [
    StickerCategory('Tape', 'tape',
        ['tape_1.svg', 'tape_2.svg', 'tape_3.svg', 'tape_4.svg']),
    StickerCategory('Love', 'love',
        ['heart_solid.svg', 'heart_outline.svg', 'arrow_heart.svg', 'lips.svg']),
    StickerCategory('Notes', 'notes',
        ['note_sticky.svg', 'pin.svg', 'paperclip.svg', 'star_note.svg']),
    StickerCategory('Birthday', 'birthday', [
      'cake.svg',
      'balloon.svg',
      'gift.svg',
      'party_hat.svg',
      'confetti.svg',
    ]),
    StickerCategory('Paint', 'paint',
        ['brush_stroke.svg', 'splatter.svg', 'drip.svg', 'blob.svg']),
    StickerCategory('Frame', 'frame', [
      'frame_square.svg',
      'frame_rounded.svg',
      'frame_polaroid.svg',
      'corner.svg',
    ]),
    StickerCategory('Christmas', 'christmas', [
      'tree.svg',
      'snowman.svg',
      'bauble.svg',
      'candy_cane.svg',
      'santa_hat.svg',
    ]),
    StickerCategory('New Year', 'newyear',
        ['firework.svg', 'champagne.svg', 'star_burst.svg', 'clock.svg']),
    StickerCategory('Winter', 'winter',
        ['snowflake.svg', 'mitten.svg', 'snow_pile.svg', 'cloud_snow.svg']),
  ];
}
