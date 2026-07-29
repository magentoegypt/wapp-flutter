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

  Future<void> _restore() async {
    if (!await _repo.hasStoredToken()) {
      state = state.copyWith(status: AuthStatus.signedOut);
      return;
    }
    try {
      final Session session = await _repo.me();
      state = state.copyWith(status: AuthStatus.signedIn, session: session);
    } on Failure {
      // A stored token that no longer works is the same as none. The API
      // client has already cleared it.
      state = state.copyWith(status: AuthStatus.signedOut);
    }
  }

  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(busy: true, clearFailure: true);
    try {
      final Session session = await _repo.login(
        email: email,
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
    }
  }

  Future<void> logout() async {
    await _repo.logout();
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
