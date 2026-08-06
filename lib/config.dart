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
}
