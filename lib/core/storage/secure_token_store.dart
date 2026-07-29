import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keychain-backed storage for the Sanctum personal access token.
///
/// Two iOS Keychain behaviours are worked around here, both learned the hard
/// way on a previous app — keep them:
///
/// * `write()` deletes before writing. A plain write on an existing key can
///   fail with `errSecDuplicateItem` rather than overwriting.
/// * `clear()` deletes across **both** `synchronizable: false` and `true`.
///   The default delete leaves an iCloud-synced copy alive, so a "signed out"
///   device silently resurrects the old token on the next launch.
class SecureTokenStore {
  const SecureTokenStore(this._storage);

  final FlutterSecureStorage _storage;

  static const String _tokenKey = 'auth_token';

  static const IOSOptions _iosPlain =
      IOSOptions(synchronizable: false, accessibility: KeychainAccessibility.first_unlock);
  static const IOSOptions _iosSynced =
      IOSOptions(synchronizable: true, accessibility: KeychainAccessibility.first_unlock);

  Future<String?> read() =>
      _storage.read(key: _tokenKey, iOptions: _iosPlain);

  Future<void> write(String token) async {
    // Clear first — see the note above about errSecDuplicateItem.
    await _storage.delete(key: _tokenKey, iOptions: _iosPlain);
    await _storage.write(key: _tokenKey, value: token, iOptions: _iosPlain);
  }

  /// Removes the token from both keychain accessibility domains.
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey, iOptions: _iosPlain);
    await _storage.delete(key: _tokenKey, iOptions: _iosSynced);
  }

  Future<bool> get hasToken async => (await read())?.isNotEmpty ?? false;
}

final secureTokenStoreProvider = Provider<SecureTokenStore>(
  (ref) => const SecureTokenStore(FlutterSecureStorage()),
);
