import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_token_store.dart';
import '../domain/session.dart';

/// Auth operations, in domain terms. The presentation layer never sees a path,
/// a status code or a dio type.
abstract interface class AuthRepository {
  /// Exchanges credentials for a Sanctum personal access token and persists it.
  ///
  /// [identifier] is an **email address or a username**. The API decides which
  /// by looking for an "@" — the same split the web console makes, so both
  /// surfaces accept the same credentials. Matching is case-insensitive.
  ///
  /// Named for what it holds rather than for the wire key, which is still
  /// `email`: a parameter called `email` that accepts a username is the kind
  /// of naming that hides a bug.
  Future<Session> login({
    required String identifier,
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

  /// Completes a reset with the code from the emailed link. Revokes every
  /// token on success, so other devices are signed out.
  Future<void> resetPassword({
    required String email,
    required String token,
    required String password,
  });
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
      // Its own budget rather than the client's 20s JSON default. The endpoint
      // is meant to answer immediately — it hands the mail off to run after
      // the response — but a build talking to an API that has not picked that
      // up yet should degrade to a slow success, not the hard "server took too
      // long" error QA filmed (CL037-TC14). Same per-call hook the media and
      // contact-import uploads use.
      timeout: const Duration(seconds: 45),
    );
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String token,
    required String password,
  }) async {
    await _api.post(
      '/auth/reset-password',
      body: <String, dynamic>{
        'email': email,
        'token': token,
        'password': password,
        // Laravel's reset rule is `confirmed`, so it wants the repeat field
        // alongside. The screen validates the match before we get here.
        'password_confirmation': password,
      },
    );
  }

  @override
  Future<Session> login({
    required String identifier,
    required String password,
    required String deviceName,
  }) async {
    final dynamic body = await _api.post(
      '/auth/login',
      body: <String, dynamic>{
        // Still `email`, even for a username. The endpoint accepts `username`
        // and `login` as aliases, but `email` is the documented field and the
        // one every other client sends — no reason to be the odd one out.
        'email': identifier,
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
      permissions: _permissions(user['permissions']),
    ),
    vendor: Vendor(
      uid: (vendor['uid'] as String?) ?? '',
      // `/me` returns only uid and status for the vendor — no display name.
      name: (vendor['name'] ?? vendor['title'] ?? '') as String,
      status: (vendor['status'] as num?)?.toInt() ?? 1,
    ),
  );
}

/// Normalises the permission block to the list of granted keys.
///
/// The API sends a **map** — `{"messaging": "allow", "manage_ads": "deny", …}`
/// — not a list. Casting it to `List` threw a `TypeError` that was not a
/// [Failure], so it escaped the login controller with its busy flag still set
/// and left the sign-in button spinning forever (CL037-TC13).
///
/// A list is still accepted: `/me` and older builds send one, and an owner
/// comes back with an empty collection either way.
List<String> _permissions(dynamic raw) {
  if (raw is List) {
    return raw.map((dynamic e) => e.toString()).toList();
  }
  if (raw is Map) {
    return <String>[
      for (final MapEntry<dynamic, dynamic> e in raw.entries)
        // Anything that is not an explicit "deny" — `true`, `1`, `"allow"` —
        // counts as granted, so a backend that switches to booleans keeps
        // working.
        if (_granted(e.value)) e.key.toString(),
    ];
  }
  return const <String>[];
}

bool _granted(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final String v = value.toString().toLowerCase();
  return v == 'allow' || v == 'true' || v == '1' || v == 'yes';
}

final authRepositoryProvider = Provider<AuthRepository>((Ref ref) {
  return AuthRepositoryImpl(
    ref.watch(apiClientProvider),
    ref.watch(secureTokenStoreProvider),
  );
});
