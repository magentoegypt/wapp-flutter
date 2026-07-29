import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/util/message_text.dart';
import '../domain/conversation.dart';

/// Which slice of the inbox to load. Mirrors the filter chips on 36:1032.
enum InboxFilter { all, unread, unassigned }

abstract interface class ConversationRepository {
  Future<List<Conversation>> list({InboxFilter filter, String? query});

  Future<ChatThread> thread(String contactUid);

  Future<void> sendMessage(String contactUid, String body);

  Future<void> setStatus(String contactUid, ConversationStatus status);

  Future<int> unreadCount();
}

class ConversationRepositoryImpl implements ConversationRepository {
  const ConversationRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<List<Conversation>> list({
    InboxFilter filter = InboxFilter.all,
    String? query,
  }) async {
    final dynamic body = await _api.get(
      '/conversations',
      query: <String, dynamic>{
        if (filter != InboxFilter.all) 'filter': filter.name,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );

    return _rows(body, 'conversations')
        .map(conversationFromJson)
        .toList();
  }

  /// The API returns `{success, filter, conversations: [...]}` — the list lives
  /// under a domain-named key, not `data`. Falls back to `data` and to a bare
  /// list so a future envelope change doesn't silently empty the screen.
  List<Map<String, dynamic>> _rows(dynamic body, String key) {
    if (body is List) return body.whereType<Map<String, dynamic>>().toList();
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final List<dynamic> raw =
        (m[key] ?? m['data']) as List<dynamic>? ?? const <dynamic>[];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  @override
  Future<ChatThread> thread(String contactUid) async {
    final dynamic body = await _api.get('/conversations/$contactUid');
    return chatThreadFromJson(contactUid, body as Map<String, dynamic>);
  }

  @override
  Future<void> sendMessage(String contactUid, String body) async {
    await _api.post(
      '/conversations/$contactUid/messages',
      body: <String, dynamic>{'message': body},
    );
  }

  @override
  Future<void> setStatus(String contactUid, ConversationStatus status) async {
    await _api.post(
      '/conversations/$contactUid/status',
      body: <String, dynamic>{'status': status.value},
    );
  }

  @override
  Future<int> unreadCount() async {
    final dynamic body = await _api.get('/conversations/unread-count');
    if (body is num) return body.round();
    // `{success, unread, conversations}` — `unread` is the message count,
    // `conversations` the number of threads carrying them.
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return _int(m['unread'] ?? m['count']);
  }
}

DateTime? _date(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// Never throws on an unexpected type — a malformed count degrades to 0
/// rather than taking down the whole inbox list.
int _int(Object? v) => v is num ? v.round() : int.tryParse('${v ?? ''}') ?? 0;

Conversation conversationFromJson(Map<String, dynamic> j) {
  // `lastMessage` is an object — {body, isIncoming, messagedAt} — not a string.
  final Map<String, dynamic> last =
      (j['lastMessage'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

  return Conversation(
    contactUid: (j['uid'] ?? j['contactUid'] ?? '').toString(),
    name: (j['name'] ?? j['waId'] ?? '').toString(),
    lastMessage: MessageText.plain((last['body'] ?? '').toString()),
    lastMessageAt: _date(last['messagedAt']),
    unreadCount: _int(j['unread'] ?? j['unreadCount']),
    status: ConversationStatus.fromApi(j['status']),
    assignedAgentName: (j['assignedUserName'] ?? j['assignedAgent']) as String?,
    isIncomingLast: (last['isIncoming'] as bool?) ?? true,
  );
}

ChatThread chatThreadFromJson(String contactUid, Map<String, dynamic> j) {
  final Map<String, dynamic> contact =
      (j['contact'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

  // `replyLock` is an object; `locked == false` means the chat is unclaimed.
  final Map<String, dynamic> lock =
      (j['replyLock'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
  final bool locked = (lock['locked'] as bool?) ?? false;

  return ChatThread(
    contactUid: contactUid,
    name: (contact['name'] ?? contact['waId'] ?? '').toString(),
    phone: (contact['waId'] ?? contact['phone']) as String?,
    messages: ((j['messages'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(chatMessageFromJson)
        .toList(),
    // The API renames the engine's isDirectMessageDeliveryWindowOpened to
    // `windowOpen`, but passes conversationExpiresAt through verbatim.
    windowOpen: (j['windowOpen'] as bool?) ?? false,
    windowExpiresAt: _date(j['conversationExpiresAt']),
    // Chat detail carries no canned replies; the composer chips are sourced
    // from the quick-replies endpoint instead.
    quickReplies: const <String>[],
    assignedAgentName:
        (j['chatOwnerName'] as String?)?.trim().isEmpty ?? true
            ? null
            : (j['chatOwnerName'] as String?),
    replyLockHeldBy: locked
        ? ((lock['lockedByName'] as String?) ?? 'another agent')
        : null,
  );
}

ChatMessage chatMessageFromJson(Map<String, dynamic> j) {
  return ChatMessage(
    uid: (j['uid'] ?? '').toString(),
    body: MessageText.plain((j['body'] ?? j['message'] ?? '').toString()),
    isIncoming: (j['isIncoming'] as bool?) ?? false,
    sentAt: _date(j['messagedAt']),
    status: j['status'] as String?,
    agentName: (j['agent'] ?? j['agent_name']) as String?,
  );
}

final conversationRepositoryProvider = Provider<ConversationRepository>(
  (Ref ref) => ConversationRepositoryImpl(ref.watch(apiClientProvider)),
);

/// Active inbox filter, shared between the chip bar and the list.
final inboxFilterProvider = StateProvider<InboxFilter>((Ref ref) => InboxFilter.all);

final inboxListProvider =
    FutureProvider.autoDispose<List<Conversation>>((Ref ref) {
  final InboxFilter filter = ref.watch(inboxFilterProvider);
  return ref.watch(conversationRepositoryProvider).list(filter: filter);
});

final chatThreadProvider =
    FutureProvider.autoDispose.family<ChatThread, String>((Ref ref, String uid) {
  return ref.watch(conversationRepositoryProvider).thread(uid);
});
