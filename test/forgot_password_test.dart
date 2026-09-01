import 'dart:convert';
import 'dart:typed_data';

import 'package:clickalize/core/error/failure.dart';
import 'package:clickalize/core/network/api_client.dart';
import 'package:clickalize/core/storage/secure_token_store.dart';
import 'package:clickalize/features/auth/data/auth_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Forgot password, at the seam where the API's answer becomes a [Failure].
///
/// The reset endpoint is throttled at five attempts per address, and a tester
/// tapping "Send link" repeatedly is exactly how you find that out. The client
/// had no 429 branch, so the throttle's own message — which names how many
/// seconds are left — was replaced by "Request failed (429)." (CL037-TC14).
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.statusCode, this.body);

  final int statusCode;
  final Map<String, dynamic> body;

  /// Recorded so a test can show the call went where it claims.
  String? lastPath;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastPath = options.path;
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

AuthRepository _repositoryOn(_StubAdapter adapter) {
  const SecureTokenStore tokens = SecureTokenStore(FlutterSecureStorage());
  return AuthRepositoryImpl(
    ApiClient(tokens, dio: Dio()..httpClientAdapter = adapter),
    tokens,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test('a throttled reset shows the server\'s message, not "Request failed"',
      () async {
    final _StubAdapter adapter = _StubAdapter(429, <String, dynamic>{
      'success': false,
      'message': 'Too many attempts. Try again in 847 seconds.',
    });

    await expectLater(
      _repositoryOn(adapter).forgotPassword('someone@example.com'),
      throwsA(
        isA<RateLimitFailure>().having(
          (RateLimitFailure f) => f.message,
          'message',
          'Too many attempts. Try again in 847 seconds.',
        ),
      ),
    );

    expect(adapter.lastPath, '/auth/forgot-password');
  });

  test('a throttle with no body still avoids the raw status code', () async {
    await expectLater(
      _repositoryOn(_StubAdapter(429, <String, dynamic>{}))
          .forgotPassword('someone@example.com'),
      throwsA(
        isA<RateLimitFailure>().having(
          (RateLimitFailure f) => f.message,
          'message',
          isNot(contains('429')),
        ),
      ),
    );
  });

  test('the ordinary 200 resolves quietly', () async {
    // The endpoint answers identically for every address, so there is nothing
    // to assert beyond "it did not throw" — which is the whole contract.
    await expectLater(
      _repositoryOn(
        _StubAdapter(200, <String, dynamic>{
          'success': true,
          'message': 'If that address belongs to an account, a reset link is '
              'on its way.',
        }),
      ).forgotPassword('someone@example.com'),
      completes,
    );
  });
}
