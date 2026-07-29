import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/storage/locale_prefs.dart';

/// Shared startup for every flavor entrypoint: initialise storage, build the
/// provider container with concrete overrides, then run the app.
///
/// The flavor itself is compiled in via `--dart-define-from-file`, so there is
/// nothing to branch on here.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Locale date symbols, so Arabic renders Arabic month and day names rather
  // than falling back to English.
  await initializeDateFormatting();

  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      localePrefsProvider.overrideWithValue(LocalePrefs(prefs)),
    ],
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ClickalizeApp(),
    ),
  );
}
