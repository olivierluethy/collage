import 'package:flutter_test/flutter_test.dart';

import 'package:collage/models/remote_catalog.dart';

void main() {
  group('remote catalog parsing', () {
    const json = {
      'fonts': [
        {'key': 'bangers', 'family': 'Bangers', 'googleFont': 'Bangers'},
        {'family': 'Solo', 'url': 'https://cdn.example/solo.ttf'},
      ],
      'categories': [
        {
          'id': 'emoji',
          'label': 'Emoji',
          'stickers': [
            {'name': 'smile', 'url': 'https://cdn.example/smile.svg'},
            {'name': 'wink', 'url': 'https://cdn.example/wink.png'},
          ],
        },
      ],
    };

    test('reads fonts and sticker categories', () {
      final c = RemoteCatalogs.fromJson(json);
      expect(c.fonts.length, 2);
      expect(c.fonts.first.key, 'bangers');
      expect(c.fonts.first.googleFont, 'Bangers');
      expect(c.stickerCategories.single.label, 'Emoji');
      expect(c.stickerCategories.single.stickers.length, 2);
      expect(c.isEmpty, isFalse);
    });

    test('a font with no key falls back to its family', () {
      final c = RemoteCatalogs.fromJson(json);
      expect(c.fonts[1].key, 'Solo');
      expect(c.fonts[1].url, 'https://cdn.example/solo.ttf');
    });

    test('round-trips through JSON', () {
      final c = RemoteCatalogs.fromJson(json);
      final back = RemoteCatalogs.fromJson(c.toJson());
      expect(back.fonts.length, c.fonts.length);
      expect(back.stickerCategories.single.stickers.last.url,
          'https://cdn.example/wink.png');
    });

    test('an empty payload yields the empty catalog', () {
      final c = RemoteCatalogs.fromJson(const {});
      expect(c.isEmpty, isTrue);
      expect(RemoteCatalogs.empty.isEmpty, isTrue);
    });
  });
}
