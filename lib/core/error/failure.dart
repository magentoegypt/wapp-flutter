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

/// No usable connection or DNS failure — the request never reached the server.
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No connection. Check your network and try again.']);
}

/// The server was reached but did not answer in time.
///
/// Kept separate from [NetworkFailure] because the remedy is different and the
/// old shared copy actively misled: a slow endpoint told the user to check
/// their network while the network was fine and every other screen was loading.
class TimeoutFailure extends Failure {
  const TimeoutFailure([
    super.message =
        'The server took too long to respond. It may be busy — try again.',
  ]);
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

/// 403 — the workspace's subscription does not include this module.
///
/// The API gates every route by plan and refuses with the same status code it
/// uses for a permission problem. The two are told apart by a single key: a
/// plan refusal carries `module`, a permission refusal does not.
///
/// Worth separating, because only one of them is the user's to fix. "You do not
/// have access to this" sends an owner to ask their admin for a permission they
/// already have, when the real answer is that the plan does not include the
/// feature. [module] is the key the server named, kept so a screen can say
/// which one.
class PlanLimitFailure extends Failure {
  const PlanLimitFailure(
    super.message, [
    this.module,
  ]);

  final String? module;
}

/// 429 — refused by a throttle, not by anything being wrong.
///
/// Deliberately not a [ServerFailure]: that one is documented as covering
/// "anything else that isn't actionable by the user", and waiting is exactly
/// an action the user can take. The server's own message names how long, so it
/// is carried through rather than replaced — a generic "try again later"
/// would throw away the number of seconds.
class RateLimitFailure extends Failure {
  const RateLimitFailure([
    super.message = 'Too many attempts. Please wait a moment and try again.',
  ]);
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
