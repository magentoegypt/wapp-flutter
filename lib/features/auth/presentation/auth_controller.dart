import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../data/auth_repository.dart';
import '../domain/session.dart';

/// Where the user is in the sign-in lifecycle. The router redirect reads this,
/// so it must be synchronous and always defined.
enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.session,
    this.busy = false,
    this.failure,
  });

  final AuthStatus status;
  final Session? session;
  final bool busy;
  final Failure? failure;

  AuthState copyWith({
    AuthStatus? status,
    Session? session,
    bool? busy,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      session: session ?? this.session,
      busy: busy ?? this.busy,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Resolve any stored token in the background; the router shows Login until
    // this settles.
    Future<void>.microtask(_restore);
    return const AuthState();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// How long the branded splash stays up at minimum.
  ///
  /// Session restore is often faster than a frame or two, which made the splash
  /// flash and disappear. This is a floor, not a sleep: it runs *concurrently*
  /// with the network call below, so a slow restore is never made slower — the
  /// wait only applies when resolving finished early.
  static const Duration _minimumSplash = Duration(milliseconds: 1800);

  Future<void> _restore() async {
    // Started before any awaiting so the clock covers the whole restore.
    final Future<void> floor = Future<void>.delayed(_minimumSplash);
    try {
      if (!await _repo.hasStoredToken()) {
        await floor;
        state = state.copyWith(status: AuthStatus.signedOut);
        return;
      }
      final Session session = await _repo.me();
      await floor;
      state = state.copyWith(status: AuthStatus.signedIn, session: session);
    } catch (error, stack) {
      await floor;
      // Catch **everything**, not just Failure. A parse or cast error escaping
      // here would leave status on `unknown`, and the router's redirect treats
      // `unknown` as "hold on Login" — stranding the app at the sign-in screen
      // forever with a perfectly valid token and no visible error.
      // Degrading to signedOut is recoverable; hanging in `unknown` is not.
      debugPrint('[auth] session restore failed: $error');
      debugPrintStack(stackTrace: stack, maxFrames: 8);
      state = state.copyWith(status: AuthStatus.signedOut);
    }
  }

  Future<bool> login({
    required String identifier,
    required String password,
  }) async {
    state = state.copyWith(busy: true, clearFailure: true);
    try {
      final Session session = await _repo.login(
        identifier: identifier,
        password: password,
        deviceName: _deviceName(),
      );
      state = state.copyWith(
        status: AuthStatus.signedIn,
        session: session,
        busy: false,
      );
      return true;
    } on Failure catch (e) {
      state = state.copyWith(busy: false, failure: e);
      return false;
    } catch (error, stack) {
      // Catch **everything**, for the same reason `_restore` does. Anything
      // that is not a Failure — a cast error on an unexpected login envelope,
      // a keychain PlatformException while storing the token — used to escape
      // this method with `busy` still true, which disables the button and
      // leaves its spinner turning for good: the screen looks like it is
      // signing in forever, with no error and no way to retry.
      debugPrint('[auth] login failed: $error');
      debugPrintStack(stackTrace: stack, maxFrames: 8);
      state = state.copyWith(busy: false, failure: const ServerFailure());
      return false;
    }
  }

  /// Ends the session on this device.
  ///
  /// The terminal state is unconditional. [AuthRepository.logout] clears the
  /// stored token in its own `finally`, so by the time anything here can go
  /// wrong the credential is already gone — and leaving `status` on `signedIn`
  /// because the revoke call failed produced the worst state available: signed
  /// in with no token, every request 401ing, and a Sign out row that looked
  /// dead. QA filmed that as "you have to press it a lot" (CL037-TC16),
  /// because each extra tap fired another concurrent revoke and whichever
  /// landed first was the one that appeared to work.
  Future<void> logout() async {
    // One at a time, for the same reason [ScreenPoll] guards its tick: without
    // this a slow network turns every impatient tap into another request.
    if (state.busy) return;
    state = state.copyWith(busy: true, clearFailure: true);
    try {
      await _repo.logout();
    } catch (error, stack) {
      // Swallowed on purpose. A failed revoke only means the token stays valid
      // server-side until it expires; that is never a reason to keep someone
      // signed in on the phone in front of them.
      debugPrint('[auth] logout failed: $error');
      debugPrintStack(stackTrace: stack, maxFrames: 8);
    } finally {
      // `const AuthState(...)` rather than copyWith: it clears `busy` and
      // `failure` in the same assignment, so Login never opens carrying the
      // banner from a sign-out that went wrong.
      state = const AuthState(status: AuthStatus.signedOut);
    }
  }

  /// The server rejected the stored token. [ApiClient] has already cleared it,
  /// so this only has to move the app onto the signed-out surface.
  ///
  /// The callback behind this was declared and never wired, which meant a token
  /// revoked from the web console cleared the keychain and then left the app on
  /// whatever screen it was on, every request failing, until it was relaunched.
  void expire() {
    // Only a live session. `unknown` belongs to [_restore], which owns the
    // minimum-splash floor and would have it cut short by a 401 on `/me`; and a
    // 401 during sign-in is a wrong password, where this would wipe the
    // `failure` the form is about to show.
    if (state.status != AuthStatus.signedIn) return;
    state = const AuthState(status: AuthStatus.signedOut);
  }

  /// Labels the token in the user's session list, so a lost phone can be
  /// revoked individually rather than rotating everything.
  String _deviceName() {
    if (kIsWeb) return 'Web';
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return 'Mobile';
    }
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
