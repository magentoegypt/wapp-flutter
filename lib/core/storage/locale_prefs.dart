import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret preference storage for the chosen UI language.
///
/// Secrets never come through here — auth tokens live in [SecureTokenStore],
/// backed by the platform keychain.
class LocalePrefs {
  const LocalePrefs(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'locale_code';

  /// `null` on first launch, before the user has chosen.
  String? read() => _prefs.getString(_key);

  Future<void> write(String languageCode) =>
      _prefs.setString(_key, languageCode);
}

/// Overridden in `bootstrap()` with the resolved SharedPreferences instance.
final localePrefsProvider = Provider<LocalePrefs>(
  (ref) => throw UnimplementedError('localePrefsProvider must be overridden in bootstrap()'),
);
