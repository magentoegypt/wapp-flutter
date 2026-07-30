import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_token_store.dart';
import '../domain/session.dart';

/// Auth operations, in domain terms. The presentation layer never sees a path,
/// a status code or a dio type.
abstract interface class AuthRepository {
  /// Exchanges credentials for a Sanctum personal access token and persists it.
  Future<Session> login({
    required String email,
    required String password,
    required String deviceName,
  });

  /// Revokes the current token server-side, then clears it locally. Local
  /// state is cleared even if the network call fails — a user who taps sign out
  /// must end up signed out on this device regardless.
  Future<void> logout();

  Future<Session> me();

  Future<bool> hasStoredToken();

  /// Asks the API to email a reset link.
  ///
  /// Always resolves for a well-formed address, whether or not an account
  /// exists — the endpoint answers 200 either way on purpose, because a
  /// 200-vs-500 difference would be an account-enumeration oracle. So the UI
  /// must never claim the address was found.
  Future<void> forgotPassword(String email);
}

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._api, this._tokens);

  final ApiClient _api;
  final SecureTokenStore _tokens;

  @override
  Future<void> forgotPassword(String email) async {
    await _api.post(
      '/auth/forgot-password',
      body: <String, dynamic>{'email': email},
    );
  }

  @override
  Future<Session> login({
    required String email,
    required String password,
    required String deviceName,
  }) async {
    final dynamic body = await _api.post(
      '/auth/login',
      body: <String, dynamic>{
        'email': email,
        'password': password,
        'device_name': deviceName,
      },
    );

    final Session session = sessionFromJson(body as Map<String, dynamic>);
    await _tokens.write(session.token);
    return session;
  }

  @override
  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } finally {
      await _tokens.clear();
    }
  }

  @override
  Future<Session> me() async {
    final dynamic body = await _api.get('/me');
    final Map<String, dynamic> map = body as Map<String, dynamic>;
    // /me has no token field — carry the stored one through so callers get a
    // complete Session either way.
    return sessionFromJson(<String, dynamic>{
      ...map,
      'token': map['token'] ?? '',
    });
  }

  @override
  Future<bool> hasStoredToken() => _tokens.hasToken;
}

/// Maps the API envelope to domain types. Tolerant of missing optional fields
/// so a backend addition never crashes an older client.
Session sessionFromJson(Map<String, dynamic> json) {
  final Map<String, dynamic> user =
      (json['user'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
  final Map<String, dynamic> vendor =
      (json['vendor'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

  return Session(
    token: (json['token'] as String?) ?? '',
    user: AgentUser(
      uid: (user['uid'] as String?) ?? '',
      name: (user['name'] as String?) ?? '',
      email: (user['email'] as String?) ?? '',
      role: (user['role'] as String?) ?? 'agent',
      permissions: ((user['permissions'] as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(),
    ),
    vendor: Vendor(
      uid: (vendor['uid'] as String?) ?? '',
      // `/me` returns only uid and status for the vendor — no display name.
      name: (vendor['name'] ?? vendor['title'] ?? '') as String,
      status: (vendor['status'] as num?)?.toInt() ?? 1,
    ),
  );
}

final authRepositoryProvider = Provider<AuthRepository>((Ref ref) {
  return AuthRepositoryImpl(
    ref.watch(apiClientProvider),
    ref.watch(secureTokenStoreProvider),
  );
});
