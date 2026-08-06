import 'package:shared_preferences/shared_preferences.dart';

/// Small key/value store for first-run flags (onboarding, coach-marks).
class PrefsService {
  PrefsService(this._prefs);
  final SharedPreferences _prefs;

  static Future<PrefsService> create() async =>
      PrefsService(await SharedPreferences.getInstance());

  static const _kOnboardingDone = 'onboarding_done';
  static const _kCoachPrefix = 'coach_';

  bool get onboardingDone => _prefs.getBool(_kOnboardingDone) ?? false;
  Future<void> setOnboardingDone() => _prefs.setBool(_kOnboardingDone, true);

  bool coachSeen(String id) => _prefs.getBool('$_kCoachPrefix$id') ?? false;
  Future<void> setCoachSeen(String id) => _prefs.setBool('$_kCoachPrefix$id', true);

  Future<void> resetGuides() async {
    for (final k in _prefs.getKeys().toList()) {
      if (k.startsWith(_kCoachPrefix) || k == _kOnboardingDone) {
        await _prefs.remove(k);
      }
    }
  }
}
