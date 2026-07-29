import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
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

    // Accept both a bare list and a paginated `{data: [...]}` envelope, since
    // Laravel resources default to the latter.
    final List<dynamic> rows = body is List
        ? body
        : ((body as Map<String, dynamic>)['data'] as List<dynamic>? ??
            const <dynamic>[]);

    return rows
        .whereType<Map<String, dynamic>>()
        .map(conversationFromJson)
        .toList();
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
    return ((body as Map<String, dynamic>)['count'] as num?)?.round() ?? 0;
  }
}

DateTime? _date(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// Never throws on an unexpected type — a malformed count degrades to 0
/// rather than taking down the whole inbox list.
int _int(Object? v) => v is num ? v.round() : int.tryParse('${v ?? ''}') ?? 0;

Conversation conversationFromJson(Map<String, dynamic> j) {
  return Conversation(
    contactUid: (j['contactUid'] ?? j['contact_uid'] ?? j['uid'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    lastMessage: (j['lastMessage'] ?? j['last_message'] ?? '').toString(),
    lastMessageAt: _date(j['lastMessageAt'] ?? j['last_message_at']),
    unreadCount: _int(j['unreadCount'] ?? j['unread_count']),
    status: ConversationStatus.fromValue((j['status'] as num?)?.toInt()),
    assignedAgentName: (j['assignedAgent'] ?? j['assigned_agent']) as String?,
    isIncomingLast: (j['isIncomingLast'] ?? j['is_incoming_last']) as bool? ?? true,
  );
}

ChatThread chatThreadFromJson(String contactUid, Map<String, dynamic> j) {
  final Map<String, dynamic> contact =
      (j['contact'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

  return ChatThread(
    contactUid: contactUid,
    name: (contact['name'] ?? j['name'] ?? '').toString(),
    phone: (contact['phone'] ?? contact['wa_id']) as String?,
    messages: ((j['messages'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(chatMessageFromJson)
        .toList(),
    // Backend field names are passed through verbatim from the engine.
    windowOpen: (j['isDirectMessageDeliveryWindowOpened'] as bool?) ?? false,
    windowExpiresAt: _date(j['conversationExpiresAt']),
    quickReplies: ((j['quickReplies'] as List<dynamic>?) ?? const <dynamic>[])
        .map((dynamic e) => e is Map ? (e['title'] ?? '').toString() : e.toString())
        .where((String s) => s.isNotEmpty)
        .toList(),
    assignedAgentName:
        (j['assigned'] as Map<String, dynamic>?)?['agentName'] as String?,
    replyLockHeldBy:
        (j['smartRoutingLock'] as Map<String, dynamic>?)?['heldBy'] as String?,
  );
}

ChatMessage chatMessageFromJson(Map<String, dynamic> j) {
  return ChatMessage(
    uid: (j['uid'] ?? '').toString(),
    body: (j['body'] ?? j['message'] ?? '').toString(),
    isIncoming: (j['isIncoming'] ?? j['is_incoming_message']) as bool? ?? false,
    sentAt: _date(j['messagedAt'] ?? j['messaged_at']),
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
