import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/locale_prefs.dart';

/// The active UI language. Changing it rebuilds the whole tree: the font family
/// swaps (Inter ↔ Cairo), every localized string re-resolves, and the root
/// [Directionality] flips.
class LocaleController extends Notifier<Locale> {
  static const Locale english = Locale('en');
  static const Locale arabic = Locale('ar');

  @override
  Locale build() {
    final String? saved = ref.read(localePrefsProvider).read();
    return saved == 'ar' ? arabic : english;
  }

  Future<void> setLanguage(String languageCode) async {
    if (languageCode == state.languageCode) return;
    await ref.read(localePrefsProvider).write(languageCode);
    state = languageCode == 'ar' ? arabic : english;
  }

  Future<void> toggle() =>
      setLanguage(state.languageCode == 'ar' ? 'en' : 'ar');
}

final localeControllerProvider =
    NotifierProvider<LocaleController, Locale>(LocaleController.new);

/// Text direction derived from the active locale. Read this rather than
/// checking the language code at call sites.
final isRtlProvider = Provider<bool>(
  (ref) => ref.watch(localeControllerProvider).languageCode == 'ar',
);
