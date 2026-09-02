import 'package:clickalize/app/app.dart';
import 'package:clickalize/app/router.dart';
import 'package:clickalize/app/routes.dart';
import 'package:clickalize/core/network/api_client.dart';
import 'package:clickalize/core/storage/locale_prefs.dart';
import 'package:clickalize/features/auth/data/auth_repository.dart';
import 'package:clickalize/features/auth/domain/session.dart';
import 'package:clickalize/features/auth/presentation/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signing out.
///
/// QA filmed this as "sometimes the logout button doesn't work and you have to
/// press it a lot to actually log out" (CL037-TC16). Three faults compounded,
/// and every one of them is silent on its own:
///
/// * `state = signedOut` sat *after* an unguarded `await`, so any failure on
///   the revoke call skipped it — while the repository had already cleared the
///   token in its own `finally`. That left the app signed in with no
///   credential, which is worse than either end state.
/// * Nothing marked the controller busy, so the row neither disabled nor spun
///   through a call that can take seconds.
/// * Nothing guarded re-entry, so each impatient tap fired another concurrent
///   revoke and whichever landed first was the one that appeared to work.
///
/// The obvious wrong turn is to fix only the third: a guard makes the extra
/// taps cheap but still leaves the first one able to fail silently. What has to
/// hold is that **one** press always ends the session, whatever the network
/// does.
class _Boom implements Exception {
  const _Boom();

  @override
  String toString() => 'revoke failed';
}

/// Stands in for the whole repository, so a throwing [logout] models the real
/// contract: the token is already cleared locally and only the server-side
/// revoke went wrong.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({
    this.signedIn = true,
    this.logoutFails = false,
    this.logoutDelay = Duration.zero,
  });

  final bool signedIn;
  final bool logoutFails;
  final Duration logoutDelay;

  int logoutCalls = 0;

  static const Session _session = Session(
    token: 'test-token',
    user: AgentUser(uid: 'u1', name: 'Hassan Ali', email: 'hassan@example.com'),
    vendor: Vendor(uid: 'v1', name: 'Test Workspace'),
  );

  @override
  Future<void> logout() async {
    logoutCalls++;
    if (logoutDelay > Duration.zero) {
      await Future<void>.delayed(logoutDelay);
    }
    if (logoutFails) throw const _Boom();
  }

  @override
  Future<bool> hasStoredToken() async => signedIn;

  @override
  Future<Session> me() async {
    if (!signedIn) throw const _Boom();
    return _session;
  }

  @override
  Future<Session> login({
    required String identifier,
    required String password,
    required String deviceName,
  }) async =>
      _session;

  @override
  Future<void> forgotPassword(String email) async {}

  @override
  Future<void> resetPassword({
    required String email,
    required String token,
    required String password,
  }) async {}
}

/// A container whose session has finished restoring.
///
/// `_restore` holds an 1800 ms splash floor, so nothing is signed in until the
/// clock is past it. These are [testWidgets] purely for that fake clock — pump
/// is the only way to skip the floor without waiting out two real seconds per
/// test.
Future<ProviderContainer> _restored(
  WidgetTester tester,
  _FakeAuthRepository repo,
) async {
  await tester.pumpWidget(const SizedBox.shrink());

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[authRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);

  container.read(authControllerProvider);
  await tester.pump(const Duration(seconds: 2));
  return container;
}

AuthState _state(ProviderContainer c) => c.read(authControllerProvider);

AuthController _auth(ProviderContainer c) =>
    c.read(authControllerProvider.notifier);

// ---------------------------------------------------------------------------
// Full-app harness, for the two halves of the test case: cancel keeps the
// session, confirm reaches Login. Mirrors app_smoke_test's setup.
// ---------------------------------------------------------------------------

Future<ProviderContainer> _appContainer(_FakeAuthRepository repo) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  return ProviderContainer(
    overrides: <Override>[
      localePrefsProvider.overrideWithValue(LocalePrefs(prefs)),
      authRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

/// pumpAndSettle never returns inside the shell — the dashboard keeps a
/// progress indicator up because its request never resolves under the test stub
/// — so a fixed number of frames stands in for it, as in app_smoke_test.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _pumpAppOnMore(
  WidgetTester tester,
  ProviderContainer container,
) async {
  // More is a ListView and Sign out is its last row, so at the default 800x600
  // it is never built and `find.text` reports nothing at all rather than
  // something off-screen. Give the test a phone-shaped viewport tall enough to
  // hold the whole list.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(420, 1400);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const ClickalizeApp(),
    ),
  );
  await _settle(tester);
  final GoRouter router = container.read(routerProvider);
  router.go(AppRoutes.more);
  await _settle(tester);
  expect(
    router.routerDelegate.currentConfiguration.uri.toString(),
    AppRoutes.more,
  );
}

/// The row and both dialog labels all read "Sign out", so the button has to be
/// addressed through the dialog rather than by text alone.
Finder _dialogButton(String label) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, label),
    );

void main() {
  group('the controller', () {
    testWidgets('a failing revoke still ends the session', (
      WidgetTester tester,
    ) async {
      // The regression QA filmed. The token is gone either way by the time this
      // throws, so staying signed in is never the safer branch.
      final _FakeAuthRepository repo = _FakeAuthRepository(logoutFails: true);
      final ProviderContainer c = await _restored(tester, repo);
      expect(_state(c).status, AuthStatus.signedIn);

      await _auth(c).logout();

      expect(_state(c).status, AuthStatus.signedOut);
      expect(_state(c).session, isNull);
      expect(_state(c).busy, isFalse, reason: 'a stuck spinner is the other bug');
      expect(
        _state(c).failure,
        isNull,
        reason: 'Login must not open carrying a banner about the sign-out',
      );
    });

    testWidgets('a successful revoke ends the session', (
      WidgetTester tester,
    ) async {
      final ProviderContainer c = await _restored(tester, _FakeAuthRepository());
      await _auth(c).logout();
      expect(_state(c).status, AuthStatus.signedOut);
    });

    testWidgets('it is busy while the revoke is in flight', (
      WidgetTester tester,
    ) async {
      final ProviderContainer c = await _restored(
        tester,
        _FakeAuthRepository(logoutDelay: const Duration(seconds: 5)),
      );

      final Future<void> pending = _auth(c).logout();
      await tester.pump();
      expect(
        _state(c).busy,
        isTrue,
        reason: 'the row has nothing to show otherwise',
      );
      expect(_state(c).status, AuthStatus.signedIn, reason: 'not yet');

      await tester.pump(const Duration(seconds: 6));
      await pending;
      expect(_state(c).busy, isFalse);
      expect(_state(c).status, AuthStatus.signedOut);
    });

    testWidgets('impatient taps do not stack up into extra revokes', (
      WidgetTester tester,
    ) async {
      final _FakeAuthRepository repo =
          _FakeAuthRepository(logoutDelay: const Duration(seconds: 5));
      final ProviderContainer c = await _restored(tester, repo);

      final Future<void> first = _auth(c).logout();
      await tester.pump();
      // Four more taps while the first is still in flight — the shape of the
      // filmed bug, where each one used to fire its own request.
      for (int i = 0; i < 4; i++) {
        await _auth(c).logout();
      }
      expect(repo.logoutCalls, 1);

      await tester.pump(const Duration(seconds: 6));
      await first;
      expect(repo.logoutCalls, 1);
      expect(_state(c).status, AuthStatus.signedOut);
    });
  });

  group('expire', () {
    testWidgets('a rejected token signs a live session out', (
      WidgetTester tester,
    ) async {
      final ProviderContainer c = await _restored(tester, _FakeAuthRepository());
      expect(_state(c).status, AuthStatus.signedIn);

      _auth(c).expire();

      expect(_state(c).status, AuthStatus.signedOut);
      expect(_state(c).session, isNull);
    });

    testWidgets('it leaves a restore in progress alone', (
      WidgetTester tester,
    ) async {
      // `unknown` belongs to _restore, which owns the minimum-splash floor.
      // Flipping the status here would cut the splash short and flash the
      // sign-in form at someone who is already authenticated.
      await tester.pumpWidget(const SizedBox.shrink());
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        ],
      );
      addTearDown(c.dispose);

      expect(_state(c).status, AuthStatus.unknown);
      _auth(c).expire();
      expect(
        _state(c).status,
        AuthStatus.unknown,
        reason: 'restore still owns this',
      );

      await tester.pump(const Duration(seconds: 2));
      expect(_state(c).status, AuthStatus.signedIn);
    });

    testWidgets('it does not disturb a signed-out screen', (
      WidgetTester tester,
    ) async {
      // Laravel answers a wrong password with 401, which reaches the same
      // callback. Acting on it there would clear the `failure` the sign-in form
      // is about to render, and the user would be told nothing at all.
      final ProviderContainer c = await _restored(
        tester,
        _FakeAuthRepository(signedIn: false),
      );
      expect(_state(c).status, AuthStatus.signedOut);

      _auth(c).expire();
      expect(_state(c).status, AuthStatus.signedOut);
    });

    testWidgets('the 401 callback is actually wired to it', (
      WidgetTester tester,
    ) async {
      // expire() is only worth anything if something calls it, and it has
      // already spent time in the tree as a method nothing did — with the
      // suite green throughout, because every other test in this group invokes
      // it directly. This is the one that fails when apiClientProvider stops
      // passing the callback.
      final ProviderContainer c = await _restored(tester, _FakeAuthRepository());
      expect(_state(c).status, AuthStatus.signedIn);

      final ApiClient client = c.read(apiClientProvider);
      expect(
        client.onUnauthenticated,
        isNotNull,
        reason: 'ApiClient drops the token on a 401 but cannot route on its own',
      );

      client.onUnauthenticated!();
      expect(_state(c).status, AuthStatus.signedOut);
    });
  });

  group('the Sign out row', () {
    testWidgets('Cancel keeps the session', (WidgetTester tester) async {
      final _FakeAuthRepository repo = _FakeAuthRepository();
      final ProviderContainer c = await _appContainer(repo);
      addTearDown(c.dispose);
      await _pumpAppOnMore(tester, c);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Sign out of this device'),
        findsOneWidget,
        reason: 'the row used to sign out on the spot, with no way back',
      );

      await tester.tap(_dialogButton('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.logoutCalls, 0);
      expect(_state(c).status, AuthStatus.signedIn);
      expect(find.text('More'), findsWidgets, reason: 'still inside the shell');
    });

    testWidgets('confirming returns to Login with the fields empty', (
      WidgetTester tester,
    ) async {
      final _FakeAuthRepository repo = _FakeAuthRepository();
      final ProviderContainer c = await _appContainer(repo);
      addTearDown(c.dispose);
      await _pumpAppOnMore(tester, c);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(_dialogButton('Sign out'));
      await _settle(tester);

      expect(repo.logoutCalls, 1);
      expect(_state(c).status, AuthStatus.signedOut);
      expect(find.text('Log in'), findsWidgets);

      // Login builds its controllers fresh, so this guards against anyone later
      // hoisting them somewhere that survives the route.
      final Iterable<EditableText> fields =
          tester.widgetList<EditableText>(find.byType(EditableText));
      expect(fields, hasLength(2));
      for (final EditableText f in fields) {
        expect(f.controller.text, isEmpty);
      }
    });
  });
}
