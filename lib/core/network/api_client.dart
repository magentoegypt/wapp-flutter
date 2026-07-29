import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../error/failure.dart';
import '../storage/secure_token_store.dart';

/// The single HTTP entry point to the Laravel mobile API.
///
/// Everything above this layer speaks in domain types and [Failure]; nothing
/// above it imports dio. Repositories call [get]/[post]/[put]/[delete] and get
/// a decoded body or a thrown [Failure] — never a `Response`, never a status
/// code.
class ApiClient {
  // Positional, because Dart only permits an initializing formal
  // (`this._tokens`) for a positional parameter — a named one cannot start
  // with an underscore.
  ApiClient(this._tokens, {Dio? dio, this.onUnauthenticated})
      : _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = AppConfig.apiBaseUrl
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 20)
      ..headers['Accept'] = 'application/json'
      // Laravel returns a redirect to the login page instead of 401 JSON
      // unless the request looks like an API call.
      ..headers['X-Requested-With'] = 'XMLHttpRequest'
      // Let the client decide what a non-2xx means rather than dio throwing
      // before the mapper runs.
      ..validateStatus = (int? code) => code != null && code < 500;

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) async {
          final String? token = await _tokens.read();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final SecureTokenStore _tokens;

  /// Invoked after the stored token has been cleared because the server
  /// rejected it. The app uses this to bounce to Login.
  final void Function()? onUnauthenticated;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get<dynamic>(path, queryParameters: query));

  Future<dynamic> post(String path, {Object? body}) =>
      _send(() => _dio.post<dynamic>(path, data: body));

  Future<dynamic> put(String path, {Object? body}) =>
      _send(() => _dio.put<dynamic>(path, data: body));

  Future<dynamic> delete(String path) =>
      _send(() => _dio.delete<dynamic>(path));

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    final Response<dynamic> response;
    try {
      response = await request();
    } on DioException catch (e) {
      throw _fromDioException(e);
    }

    final int status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return response.data;

    throw await _fromStatus(status, response.data);
  }

  Failure _fromDioException(DioException e) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError => const NetworkFailure(),
      _ => const ServerFailure(),
    };
  }

  Future<Failure> _fromStatus(int status, dynamic body) async {
    final Map<String, dynamic> map =
        body is Map<String, dynamic> ? body : const <String, dynamic>{};
    final String? serverMessage = map['message'] as String?;

    switch (status) {
      case 401:
      case 419:
        // The token is dead — drop it so the next launch starts clean, then
        // let the app route to Login.
        await _tokens.clear();
        onUnauthenticated?.call();
        return const AuthFailure();
      case 403:
        return ForbiddenFailure(serverMessage ?? 'You do not have access to this.');
      case 404:
        return NotFoundFailure(serverMessage ?? 'Not found.');
      case 422:
        return ValidationFailure(
          serverMessage ?? 'Please check the highlighted fields.',
          _parseErrors(map['errors']),
        );
      default:
        return ServerFailure(serverMessage ?? 'Request failed ($status).');
    }
  }

  /// Laravel shape: `{"errors": {"email": ["is required"], ...}}`.
  Map<String, List<String>> _parseErrors(dynamic raw) {
    if (raw is! Map) return const <String, List<String>>{};
    return raw.map(
      (dynamic key, dynamic value) => MapEntry<String, List<String>>(
        key.toString(),
        value is List
            ? value.map((dynamic e) => e.toString()).toList()
            : <String>[value.toString()],
      ),
    );
  }
}

final apiClientProvider = Provider<ApiClient>((Ref ref) {
  return ApiClient(ref.watch(secureTokenStoreProvider));
});
