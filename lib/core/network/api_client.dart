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

  /// A response that is a file rather than JSON.
  ///
  /// Two endpoints answer with bytes — the contact export workbook and the call
  /// recording. Going through [get] would hand dio's JSON transformer a binary
  /// body, which either throws or silently mangles it; `ResponseType.bytes`
  /// stops the decode before it starts.
  ///
  /// Errors still arrive as JSON, so [_send]'s mapping is reused unchanged — a
  /// 403 on an export is a plan limit like anywhere else.
  Future<List<int>> bytes(String path, {Map<String, dynamic>? query}) async {
    final Object? out = await _send(
      () => _dio.get<List<int>>(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes),
      ),
      unwrap: false,
    );
    return out is List<int> ? out : const <int>[];
  }

  /// [onSendProgress] is only meaningful for a multipart upload — dio reports
  /// bytes as they leave, which is the difference between a progress bar and a
  /// spinner that sits there for a 40MB video.
  Future<dynamic> post(
    String path, {
    Object? body,
    void Function(int sent, int total)? onSendProgress,
    Duration? timeout,
  }) =>
      _send(() => _dio.post<dynamic>(
            path,
            data: body,
            onSendProgress: onSendProgress,
            // The client's 20s default is sized for JSON. An upload needs its
            // own budget — a 40MB video on a weak mobile link takes minutes,
            // and the default would abort it partway and report a timeout that
            // looks like the server being slow.
            options: timeout == null
                ? null
                : Options(sendTimeout: timeout, receiveTimeout: timeout),
          ));

  Future<dynamic> put(String path, {Object? body}) =>
      _send(() => _dio.put<dynamic>(path, data: body));

  /// [body] because two endpoints need one on a DELETE: clearing chat history
  /// requires `{"confirm": true}`, and unsnoozing is also a DELETE. Dio allows
  /// it; only this wrapper was refusing to pass it through.
  Future<dynamic> delete(String path, {Object? body}) =>
      _send(() => _dio.delete<dynamic>(path, data: body));

  /// [unwrap] is false for a binary response: [_unwrap] inspects the body as a
  /// map, and a byte list is neither wrapped nor inspectable.
  Future<dynamic> _send(
    Future<Response<dynamic>> Function() request, {
    bool unwrap = true,
  }) async {
    final Response<dynamic> response;
    try {
      response = await request();
    } on DioException catch (e) {
      throw _fromDioException(e);
    }

    final int status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      return unwrap ? _unwrap(response.data) : response.data;
    }

    throw await _fromStatus(status, response.data);
  }

  /// Strips the API's `{"success": bool, "data": ...}` envelope.
  ///
  /// The backend wraps some responses and not others — a 401 comes back as
  /// `{"success": false, "message": "Unauthenticated."}` while a 422 is bare
  /// Laravel `{"message": ..., "errors": {...}}`. Normalising here means the
  /// repositories only ever see the payload, and stay correct whether or not
  /// a given endpoint wraps.
  ///
  /// Also catches `success: false` arriving on a 2xx, which would otherwise
  /// sail through as a valid-looking empty result.
  dynamic _unwrap(dynamic body) {
    if (body is! Map<String, dynamic>) return body;
    if (!body.containsKey('success')) return body;

    if (body['success'] == false) {
      throw ServerFailure(
        (body['message'] as String?) ?? 'Request failed.',
      );
    }

    // Unwrap only when there is a `data` key; some endpoints wrap the status
    // flag around a flat payload with no nesting.
    if (!body.containsKey('data')) return body;

    final dynamic data = body['data'];

    // Carry any sibling of `data` down with it.
    //
    // Returning `body['data']` alone silently dropped everything alongside it,
    // which is how a paginated response loses its `messagesMeta` before a
    // repository ever sees it — no error, just a thread that never loads a
    // second page. `data` wins on a key clash: it is the payload, the siblings
    // are envelope.
    //
    // Only possible when `data` is itself a Map. When it is a List there is
    // nowhere to put them, so such an endpoint has to be read unwrapped.
    if (data is Map<String, dynamic>) {
      final Map<String, dynamic> siblings = <String, dynamic>{
        for (final MapEntry<String, dynamic> e in body.entries)
          if (e.key != 'success' && e.key != 'data') e.key: e.value,
      };
      if (siblings.isEmpty) return data;
      return <String, dynamic>{...siblings, ...data};
    }

    return data;
  }

  Failure _fromDioException(DioException e) {
    return switch (e.type) {
      // Reached the server, no answer in time. Distinct from being offline:
      // telling someone to check their network when the network is fine sends
      // them to fix the wrong thing.
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => const TimeoutFailure(),
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
        // Two different refusals share this status. The plan gate names the
        // module it blocked; a permission refusal sends no such key. Only the
        // first is something the workspace owner can act on, so collapsing them
        // sends people to ask an admin for a permission they already hold.
        final String? module = map['module'] as String?;
        if (module != null && module.isNotEmpty) {
          return PlanLimitFailure(
            serverMessage ??
                'This module is not included in your current subscription plan.',
            module,
          );
        }
        return ForbiddenFailure(serverMessage ?? 'You do not have access to this.');
      case 404:
        return NotFoundFailure(serverMessage ?? 'Not found.');
      case 429:
        // Without this case a throttle fell through to `default` and was shown
        // as "Request failed (429).", burying a message the server had already
        // written for the user — the password-reset endpoint says how many
        // seconds are left. Surfaced verbatim (CL037-TC14).
        return serverMessage == null
            ? const RateLimitFailure()
            : RateLimitFailure(serverMessage);
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
