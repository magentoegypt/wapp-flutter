import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/localization/locale_controller.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../l10n/app_localizations.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Root widget.
///
/// Locale drives three things at once — the strings, the font family
/// (Inter ↔ Cairo) and the text direction — so switching language rebuilds the
/// entire tree rather than patching individual screens.
class ClickalizeApp extends ConsumerWidget {
  const ClickalizeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Locale locale = ref.watch(localeControllerProvider);
    final GoRouter router = ref.watch(routerProvider);

    // Push auth transitions into the router. `redirect` reads auth state but
    // go_router only re-evaluates it when something tells it to, so a session
    // restoring in the background would otherwise leave the app sitting on the
    // splash forever. Watching here would rebuild the GoRouter itself and
    // discard navigation history, so listen and refresh instead.
    ref.listen<AuthState>(authControllerProvider, (AuthState? prev, AuthState next) {
      if (prev?.status != next.status) router.refresh();
    });

    return MaterialApp.router(
      onGenerateTitle: (BuildContext c) => AppLocalizations.of(c).appTitle,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(locale.languageCode),
      darkTheme: AppTheme.dark(locale.languageCode),
      themeMode: ThemeMode.light,
      builder: (BuildContext context, Widget? child) => Directionality(
        textDirection:
            locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
