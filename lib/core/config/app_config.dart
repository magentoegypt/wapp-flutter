import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time configuration, supplied per flavor via
/// `--dart-define-from-file=config/{dev,staging,prod}.json`.
///
/// Every value is a `const` read of the environment so the compiler can tree
/// shake on it; nothing here is mutable or resolved at runtime. Adding a field
/// means adding it to all three JSON files.
class AppConfig {
  const AppConfig();

  /// `dev` | `staging` | `prod`.
  static const String flavor = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'dev',
  );

  /// Root of the Laravel mobile API, including the `/api/v1` segment.
  ///
  /// All three flavors currently point at wapp.magento2.click — the local
  /// XAMPP copy has no `/api/v1` layer, so there is nothing to develop
  /// against locally. **This means a dev build reads and writes production
  /// data.** Repoint dev at a local or staging install as soon as one exists.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://wapp.magento2.click/api/v1',
  );

  /// Display name — differs per flavor so testers can tell builds apart.
  static const String appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'Clickalize Dev',
  );

  static bool get isProd => flavor == 'prod';
}

final appConfigProvider = Provider<AppConfig>((ref) => const AppConfig());
