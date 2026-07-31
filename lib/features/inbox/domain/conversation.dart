import 'channel.dart';

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
    this.channel = MessageChannel.whatsapp,
    this.instagramUsername,
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

  /// Which network this arrived over. Drives the avatar badge — an agent has to
  /// know before replying, because the reply rules differ between the two.
  final MessageChannel channel;

  /// Present only on Instagram rows; null on WhatsApp.
  final String? instagramUsername;

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
    this.page = 1,
    this.hasMore = false,
    this.loadingMore = false,
    this.channel = MessageChannel.whatsapp,
  });

  final String contactUid;
  final String name;
  final String? phone;

  /// Newest first — index 0 is the most recent message.
  ///
  /// Matches both the API's pagination order and the `reverse: true` list that
  /// renders it, so index 0 lands at the bottom of the screen next to the
  /// composer. Normalised in `chatThreadFromJson`, not assumed: this contract
  /// was silently inverted once already when the endpoint changed sort order.
  /// Older pages append to the tail.
  final List<ChatMessage> messages;

  final bool windowOpen;
  final DateTime? windowExpiresAt;
  final List<String> quickReplies;
  final String? assignedAgentName;

  /// Set when another agent currently holds the smart-routing lock. Null means
  /// the chat is unclaimed — the UI invites this agent to reply first.
  final String? replyLockHeldBy;

  /// Highest page of [messages] loaded so far. Page 1 is the newest 50.
  final int page;

  /// Whether an older page exists. Once false the scroll listener stops for
  /// good rather than re-asking at every scroll.
  final bool hasMore;

  /// An older page is in flight. Renders the top spinner and blocks re-entry,
  /// so a fast flick cannot fire the same page request several times.
  final bool loadingMore;

  /// Gates the Instagram-only send controls. Posting an Instagram payload at a
  /// WhatsApp thread answers 422, so this decides whether they are offered.
  final MessageChannel channel;

  bool get isReplyLockOpen => replyLockHeldBy == null;

  ChatThread copyWith({
    List<ChatMessage>? messages,
    int? page,
    bool? hasMore,
    bool? loadingMore,
  }) {
    return ChatThread(
      contactUid: contactUid,
      name: name,
      phone: phone,
      channel: channel,
      messages: messages ?? this.messages,
      windowOpen: windowOpen,
      windowExpiresAt: windowExpiresAt,
      quickReplies: quickReplies,
      assignedAgentName: assignedAgentName,
      replyLockHeldBy: replyLockHeldBy,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
    );
  }
}

/// What kind of bubble a message is.
///
/// The server resolves this now; it used to be implicit in the shape of a JSON
/// blob, so every client re-derived it and would silently render the wrong
/// bubble the day an upstream key was renamed.
///
/// All eighteen are listed even though this install has never produced a
/// [sticker] and produces [video] once. A client that covers only what it has
/// seen renders a blank bubble the first time anything else arrives — which is
/// exactly how fifteen customer orders ended up invisible.
enum MessageKind {
  text,
  image,
  video,
  audio,
  document,
  sticker,
  location,
  locationRequest,
  contacts,
  template,
  interactiveButtons,
  interactiveList,
  ctaUrl,
  order,
  product,
  productList,
  catalog,
  unsupported,
}

extension MessageKindX on MessageKind {
  /// The API spells these snake_case (`interactive_buttons`, `location_request`).
  static MessageKind fromApi(Object? raw) {
    final String key =
        '${raw ?? ''}'.trim().toLowerCase().replaceAll('_', '');
    for (final MessageKind k in MessageKind.values) {
      if (k.name.toLowerCase() == key) return k;
    }
    // Deliberately not `text`: an unknown kind rendered as text is a bubble
    // that looks fine and says nothing. `unsupported` is honest and is the
    // API's own catch-all value.
    return raw == null ? MessageKind.text : MessageKind.unsupported;
  }

  /// Whether the bubble's meaning is carried by something other than its text.
  bool get isMedia =>
      this == MessageKind.image ||
      this == MessageKind.video ||
      this == MessageKind.audio ||
      this == MessageKind.document ||
      this == MessageKind.sticker;

  /// Commerce payloads. These are the ones that arrive with an empty body —
  /// the cart itself lives in a webhook the API strips — so they must never be
  /// rendered as a plain empty bubble.
  bool get isCommerce =>
      this == MessageKind.order ||
      this == MessageKind.product ||
      this == MessageKind.productList ||
      this == MessageKind.catalog;
}

class ChatMessage {
  const ChatMessage({
    required this.uid,
    required this.body,
    required this.isIncoming,
    required this.sentAt,
    this.kind = MessageKind.text,
    this.status,
    this.agentName,
    this.receivedOn,
  });

  final String uid;
  final String body;
  final bool isIncoming;
  final DateTime? sentAt;

  /// Resolved server-side. Defaults to [MessageKind.text] so a payload from
  /// before the typed rollout still renders as it always did.
  final MessageKind kind;

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
