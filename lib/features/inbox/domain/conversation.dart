/// Conversation state.
///
/// The API serialises this as a **string** (`"pending"`, `"open"`, …) even
/// though `contacts.status` is an integer column, so [fromApi] parses names
/// and falls back to the integer form for safety.
enum ConversationStatus {
  pending(0),
  open(1),
  solved(2),
  blocked(3);

  const ConversationStatus(this.value);

  final int value;

  static ConversationStatus fromApi(Object? raw) {
    if (raw is String) {
      return ConversationStatus.values.firstWhere(
        (ConversationStatus s) => s.name == raw.toLowerCase(),
        orElse: () => ConversationStatus.open,
      );
    }
    return switch ((raw as num?)?.toInt()) {
      0 => ConversationStatus.pending,
      2 => ConversationStatus.solved,
      3 => ConversationStatus.blocked,
      _ => ConversationStatus.open,
    };
  }
}

/// A row in the inbox list.
class Conversation {
  const Conversation({
    required this.contactUid,
    required this.name,
    required this.lastMessage,
    required this.lastMessageAt,
    this.unreadCount = 0,
    this.status = ConversationStatus.open,
    this.assignedAgentName,
    this.isIncomingLast = true,
  });

  final String contactUid;
  final String name;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final ConversationStatus status;
  final String? assignedAgentName;

  /// Whether the most recent message came from the customer — drives whether
  /// the row shows delivery ticks.
  final bool isIncomingLast;

  bool get isUnassigned => assignedAgentName == null;
}

/// The full chat payload for one contact.
///
/// [windowOpen] and [windowExpiresAt] come straight from the backend, which
/// computes the 24-hour WhatsApp service window on the fly from the contact's
/// most recent inbound message — it is never stored. The client must not try
/// to recompute it; clock skew would make the banner lie.
class ChatThread {
  const ChatThread({
    required this.contactUid,
    required this.name,
    required this.messages,
    required this.windowOpen,
    this.phone,
    this.windowExpiresAt,
    this.quickReplies = const <String>[],
    this.assignedAgentName,
    this.replyLockHeldBy,
  });

  final String contactUid;
  final String name;
  final String? phone;

  /// Oldest first. The chat view renders reversed.
  final List<ChatMessage> messages;

  final bool windowOpen;
  final DateTime? windowExpiresAt;
  final List<String> quickReplies;
  final String? assignedAgentName;

  /// Set when another agent currently holds the smart-routing lock. Null means
  /// the chat is unclaimed — the UI invites this agent to reply first.
  final String? replyLockHeldBy;

  bool get isReplyLockOpen => replyLockHeldBy == null;
}

class ChatMessage {
  const ChatMessage({
    required this.uid,
    required this.body,
    required this.isIncoming,
    required this.sentAt,
    this.status,
    this.agentName,
    this.receivedOn,
  });

  final String uid;
  final String body;
  final bool isIncoming;
  final DateTime? sentAt;

  /// `sent` | `delivered` | `read` | `failed` — outgoing only.
  final String? status;

  /// Which agent sent it, for per-bubble attribution in a shared inbox.
  final String? agentName;

  /// The workspace WhatsApp number this message came in on, from the API's
  /// `receivedOn`. Populated for 1241/1241 rows server-side; it was simply
  /// never emitted before, which is why the frame's "Received on" row rendered
  /// blank.
  final String? receivedOn;
}
