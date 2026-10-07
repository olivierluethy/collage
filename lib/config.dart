/// Build-time configuration supplied via --dart-define. No real keys are ever
/// committed; ship placeholders and document how to supply them (see README).
class Config {
  Config._();

  /// Giphy REST API key. Empty → GIF search degrades gracefully.
  static const giphyApiKey = String.fromEnvironment('GIPHY_API_KEY', defaultValue: '');

  /// Anthropic API key for AI auto-collage. Empty → feature shows a clear
  /// in-app message and manual collage-making works fully.
  static const aiApiKey = String.fromEnvironment('AI_API_KEY', defaultValue: '');

  /// Model id for the AI feature (vision-capable). Override if needed.
  static const aiModel = String.fromEnvironment('AI_MODEL', defaultValue: 'claude-opus-5');

  static bool get hasGiphy => giphyApiKey.isNotEmpty;
  static bool get hasAi => aiApiKey.isNotEmpty;

  /// Public Privacy Policy page opened from Information → Privacy Policy.
  /// Override at build time with `--dart-define=PRIVACY_POLICY_URL=...`.
  static const privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://example.com/collage/privacy',
  );

  /// Public Terms of Service page opened from Information → Terms of Service.
  /// Override at build time with `--dart-define=TERMS_URL=...`.
  static const termsOfServiceUrl = String.fromEnvironment(
    'TERMS_URL',
    defaultValue: 'https://example.com/collage/terms',
  );

  /// Remote font catalog URL (JSON). Empty → only the bundled fonts are shown.
  /// Supply with `--dart-define=FONT_CATALOG_URL=...`; see docs/CATALOGS.md.
  static const fontCatalogUrl = String.fromEnvironment(
    'FONT_CATALOG_URL',
    defaultValue: '',
  );

  /// Remote sticker catalog URL (JSON). Empty → only the bundled stickers.
  /// Supply with `--dart-define=STICKER_CATALOG_URL=...`; see docs/CATALOGS.md.
  static const stickerCatalogUrl = String.fromEnvironment(
    'STICKER_CATALOG_URL',
    defaultValue: '',
  );

  static bool get hasRemoteFonts => fontCatalogUrl.isNotEmpty;
  static bool get hasRemoteStickers => stickerCatalogUrl.isNotEmpty;
}
