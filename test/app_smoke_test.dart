import 'package:clickalize/app/app.dart';
import 'package:clickalize/app/router.dart';
import 'package:clickalize/app/routes.dart';
import 'package:clickalize/core/localization/locale_controller.dart';
import 'package:clickalize/core/storage/locale_prefs.dart';
import 'package:clickalize/features/auth/data/auth_repository.dart';
import 'package:clickalize/features/auth/domain/session.dart';
import 'package:clickalize/features/auth/presentation/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in so these tests exercise navigation, not the network.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({required this.signedIn});

  final bool signedIn;

  static const Session _session = Session(
    token: 'test-token',
    user: AgentUser(uid: 'u1', name: 'Hassan Ali', email: 'hassan@example.com'),
    vendor: Vendor(uid: 'v1', name: 'Test Workspace'),
  );

  @override
  Future<bool> hasStoredToken() async => signedIn;

  /// Records the request without a network call. The real endpoint answers 200
  /// whether or not the address exists, so there is nothing to branch on.
  String? forgotPasswordEmail;

  @override
  Future<void> forgotPassword(String email) async {
    forgotPasswordEmail = email;
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String token,
    required String password,
  }) async {}

  @override
  Future<Session> me() async {
    if (!signedIn) throw const AuthFailureStub();
    return _session;
  }

  @override
  Future<Session> login({
    required String email,
    required String password,
    required String deviceName,
  }) async =>
      _session;

  @override
  Future<void> logout() async {}
}

/// Local stand-in so the test file doesn't depend on the Failure hierarchy.
class AuthFailureStub implements Exception {
  const AuthFailureStub();
}

Future<ProviderContainer> _container({
  String? savedLocale,
  bool signedIn = true,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (savedLocale != null) 'locale_code': savedLocale,
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  return ProviderContainer(
    overrides: <Override>[
      localePrefsProvider.overrideWithValue(LocalePrefs(prefs)),
      authRepositoryProvider
          .overrideWithValue(_FakeAuthRepository(signedIn: signedIn)),
    ],
  );
}

Future<void> _pumpApp(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const ClickalizeApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signed out lands on Login', (WidgetTester tester) async {
    final ProviderContainer c = await _container(signedIn: false);
    await _pumpApp(tester, c);

    expect(c.read(authControllerProvider).status, AuthStatus.signedOut);
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets('a stored token redirects past Login to the dashboard',
      (WidgetTester tester) async {
    final ProviderContainer c = await _container(signedIn: true);
    await _pumpApp(tester, c);

    expect(c.read(authControllerProvider).status, AuthStatus.signedIn);
    // Bottom bar is present, so we are inside the shell rather than on Login.
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('an Arabic preference flips the tree to RTL',
      (WidgetTester tester) async {
    final ProviderContainer c = await _container(savedLocale: 'ar');
    await _pumpApp(tester, c);

    expect(c.read(localeControllerProvider).languageCode, 'ar');
    expect(c.read(isRtlProvider), isTrue);
    expect(
      Directionality.of(tester.element(find.byType(Scaffold).first)),
      TextDirection.rtl,
    );
  });

  testWidgets('each tab keeps its own stack', (WidgetTester tester) async {
    final ProviderContainer c = await _container();
    await _pumpApp(tester, c);
    final router = c.read(routerProvider);

    router.go(AppRoutes.chats);
    await tester.pumpAndSettle();
    router.push(AppRoutes.chat('abc-123'));
    await tester.pumpAndSettle();
    expect(find.textContaining('abc-123'), findsWidgets);

    // Switch away and back — the pushed chat must survive, which is the whole
    // reason for StatefulShellRoute over flat routes.
    router.go(AppRoutes.contacts);
    await tester.pumpAndSettle();
    router.go(AppRoutes.chats);
    await tester.pumpAndSettle();
    expect(find.textContaining('abc-123'), findsWidgets);
  });

  testWidgets('Profile keeps the bottom bar, Campaigns covers it',
      (WidgetTester tester) async {
    final ProviderContainer c = await _container();
    await _pumpApp(tester, c);
    final router = c.read(routerProvider);

    router.go(AppRoutes.profile);
    await tester.pumpAndSettle();
    expect(find.text('More'), findsWidgets);

    router.go(AppRoutes.campaigns);
    await tester.pumpAndSettle();
    expect(find.text('Campaigns'), findsWidgets);
    expect(find.text('More'), findsNothing);
  });
}
