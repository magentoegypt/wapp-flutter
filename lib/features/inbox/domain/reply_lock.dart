/// Who, if anyone, is replying to this conversation right now.
///
/// The workspace hands one agent a five-minute exclusive on replying so two
/// people do not answer the same customer at once. The lock is taken
/// automatically when someone sends, extended while they keep sending, and
/// released when it lapses.
///
/// Every field here is decided server-side, including whether the current
/// agent may take the lock away. That matters: the rule is
/// `isVendorAdmin || manage_all_team_structure || approve_incoming_transfer ||
/// approve_outgoing_transfer`, and a client re-deriving it from a role string
/// would drift from the engine the moment the permission set changed. Read
/// [canTakeover]; do not compute it.
class ReplyLock {
  const ReplyLock({
    this.locked = false,
    this.lockUid,
    this.lockedByName,
    this.lockedByCurrentUser = false,
    this.lockedUntil,
    this.canTakeover = false,
  });

  /// Nobody is replying. The composer is free for anyone.
  static const ReplyLock free = ReplyLock();

  final bool locked;
  final String? lockUid;

  /// Display name of the holder. Null when [locked] is false.
  final String? lockedByName;

  /// The holder is the signed-in agent, so there is nothing to take over and
  /// nothing to warn about — only a note that the lock is theirs.
  final bool lockedByCurrentUser;

  /// When the hold lapses, five minutes from when it was taken or last
  /// extended.
  final DateTime? lockedUntil;

  /// Whether this agent is allowed to seize it. Already accounts for the lock
  /// being their own, so it is false in that case.
  final bool canTakeover;

  /// The lock as it stands *now*, expiring it locally once [lockedUntil] has
  /// passed.
  ///
  /// Worth doing without asking the server: the hold is only five minutes long,
  /// so the overwhelmingly common way a strip goes stale is simply that it ran
  /// out while the chat sat open. Expiring it here costs nothing and keeps the
  /// screen from insisting a teammate is typing twenty minutes after they
  /// stopped. A lock *released* early by someone else still needs a refetch —
  /// this is a floor on staleness, not a substitute for one.
  ReplyLock atNow([DateTime? now]) {
    final DateTime? until = lockedUntil;
    if (!locked || until == null) return this;
    return (now ?? DateTime.now()).isBefore(until) ? this : free;
  }

  static ReplyLock fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return free;

    // `locked` is the flag to gate on. The other keys are all present and null
    // on an unlocked conversation, so testing lockedByName for null would read
    // an unlocked lock as locked-by-nobody rather than as free.
    final bool locked = (raw['locked'] as bool?) ?? false;
    if (!locked) return free;

    final String? name = (raw['lockedByName'] as String?)?.trim();

    return ReplyLock(
      locked: true,
      lockUid: raw['lockUid'] as String?,
      lockedByName: (name == null || name.isEmpty) ? null : name,
      lockedByCurrentUser: (raw['lockedByCurrentUser'] as bool?) ?? false,
      lockedUntil: DateTime.tryParse('${raw['lockedUntil'] ?? ''}')?.toLocal(),
      canTakeover: (raw['canTakeover'] as bool?) ?? false,
    );
  }

  /// Somebody else is holding it. The state the strip exists to announce, and
  /// the one that rendered nothing at all before this model existed.
  bool get heldByOther => locked && !lockedByCurrentUser;
}
