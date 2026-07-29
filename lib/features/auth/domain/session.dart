/// The signed-in agent and the workspace they belong to.
///
/// Mirrors the `POST /api/v1/auth/login` response. Vendor scoping is enforced
/// server-side from the token, so nothing here is sent back as a parameter —
/// it exists for display and for permission checks in the UI.
class Session {
  const Session({
    required this.token,
    required this.user,
    required this.vendor,
  });

  final String token;
  final AgentUser user;
  final Vendor vendor;
}

class AgentUser {
  const AgentUser({
    required this.uid,
    required this.name,
    required this.email,
    this.role = 'agent',
    this.permissions = const <String>[],
  });

  final String uid;
  final String name;
  final String email;

  /// `admin` or `agent` — derived server-side from `user_roles__id`.
  final String role;

  /// Feature permissions from `vendor_users.__data.permissions`.
  final List<String> permissions;

  bool get isAdmin => role == 'admin';
  bool can(String permission) => isAdmin || permissions.contains(permission);
}

class Vendor {
  const Vendor({required this.uid, required this.name, this.status = 1});

  final String uid;
  final String name;

  /// 1 = active.
  final int status;

  bool get isActive => status == 1;
}
