/// A transport- and backend-agnostic error.
///
/// Repositories map `DioException`, non-2xx responses and parse errors into a
/// [Failure] before returning. The presentation layer never sees a raw
/// response, a status code, or a dio type.
sealed class Failure implements Exception {
  const Failure(this.message);

  /// Safe to show a user. Never contains a stack trace, URL or token.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// No usable connection, DNS failure, or the request timed out.
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No connection. Check your network and try again.']);
}

/// 401/419 — the token is missing, expired or revoked. The API client clears
/// stored credentials and routes to Login when it sees this.
class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Your session has ended. Please sign in again.']);
}

/// 403 — authenticated, but this agent lacks the permission.
class ForbiddenFailure extends Failure {
  const ForbiddenFailure([super.message = 'You do not have access to this.']);
}

/// 404.
class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'Not found.']);
}

/// 422 — Laravel validation. [errors] is field name → messages, so a form can
/// attach each message to the right input rather than showing one blob.
class ValidationFailure extends Failure {
  const ValidationFailure(super.message, [this.errors = const {}]);

  final Map<String, List<String>> errors;

  String? forField(String field) => errors[field]?.firstOrNull;
}

/// 5xx, or anything else that isn't actionable by the user.
class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Something went wrong on our end. Try again shortly.']);
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
