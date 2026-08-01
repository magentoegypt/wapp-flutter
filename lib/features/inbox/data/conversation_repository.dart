import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/util/message_text.dart';
import '../domain/channel.dart';
import '../domain/conversation.dart';
import '../domain/message_payload.dart';
import '../domain/reply_lock.dart';

/// Which slice of the inbox to load. Mirrors the filter chips on 36:1032.
enum InboxFilter { all, unread, unassigned }

abstract interface class ConversationRepository {
  Future<List<Conversation>> list({InboxFilter filter, String? query});

  /// One page of a thread. Page 1 is the newest 50 messages.
  Future<ChatThread> thread(String contactUid, {int page});

  Future<void> sendMessage(String contactUid, String body);

  Future<void> setStatus(String contactUid, ConversationStatus status);

  Future<int> unreadCount();

  /// Who holds the five-minute reply lock, read fresh rather than from the
  /// thread payload — that copy is only as new as the last full thread fetch.
  Future<ReplyLock> replyLock(String contactUid);

  /// Seize the lock, releasing whoever held it.
  ///
  /// Refused with 403 unless the agent is an admin or carries one of the
  /// team-structure permissions, so this is only offered when the server said
  /// [ReplyLock.canTakeover].
  Future<ReplyLock> takeoverReplyLock(String contactUid);
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
  Future<ChatThread> thread(String contactUid, {int page = 1}) async {
    final dynamic body = await _api.get(
      '/conversations/$contactUid',
      query: <String, dynamic>{'page': page},
    );
    final Map<String, dynamic> map = body as Map<String, dynamic>;
    final ChatThread t = chatThreadFromJson(contactUid, map);
    return t.copyWith(
      page: page,
      hasMore: _hasMore(map, page, t.messages.length),
    );
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
  Future<ReplyLock> replyLock(String contactUid) async {
    final dynamic body = await _api.get('/conversations/$contactUid/lock');
    // The engine returns the status under `smartRoutingLock` when it rides
    // along on another response, and bare on its own endpoint. Both are read
    // so this does not break if the wrapper is added later.
    return ReplyLock.fromJson(
      body is Map<String, dynamic>
          ? (body['smartRoutingLock'] ?? body['lock'] ?? body)
          : body,
    );
  }

  @override
  Future<ReplyLock> takeoverReplyLock(String contactUid) async {
    await _api.post('/conversations/$contactUid/lock/takeover');
    // The POST answers with a message rather than the new status, so the lock
    // is re-read instead of assumed. Assuming would mean drawing "you are
    // replying now" off the back of a request whose body never said so.
    return replyLock(contactUid);
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
    channel: MessageChannelX.fromApi(j['channel']),
    instagramUsername: (j['instagramUsername'] ?? j['instagram_username']) as String?,
    isIncomingLast: (last['isIncoming'] as bool?) ?? true,
  );
}

ChatThread chatThreadFromJson(String contactUid, Map<String, dynamic> j) {
  final Map<String, dynamic> contact =
      (j['contact'] as Map<String, dynamic>?) ?? const <String, dynamic>{};

  // Guard against the endpoint answering with a *different* contact's thread.
  //
  // Observed on device: GET /conversations/{contactUid} returned the same
  // conversation for several different contact uids. The mapper used to stamp
  // the requested uid onto whatever came back, so the wrong customer's history
  // rendered under the right customer's name — and because sendMessage posts to
  // the uid in the URL, an agent could read one conversation and reply into
  // another. Refusing to show a thread we cannot vouch for is the safer failure.
  //
  // Only enforced when the payload actually echoes an identifier, so a response
  // without one behaves as before rather than failing spuriously.
  final Object? echoed =
      contact['uid'] ?? contact['contactUid'] ?? contact['contact_uid'];
  if (echoed != null &&
      '$echoed'.isNotEmpty &&
      '$echoed' != contactUid) {
    debugPrint(
      '[chat] contact mismatch: asked for $contactUid, got $echoed',
    );
    throw const ServerFailure(
      'This conversation could not be verified as belonging to this contact.',
    );
  }

  // `replyLock` is an object; `locked == false` means the chat is unclaimed.
  final Map<String, dynamic> lock =
      (j['replyLock'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
  final bool locked = (lock['locked'] as bool?) ?? false;

  return ChatThread(
    contactUid: contactUid,
    name: (contact['name'] ?? contact['waId'] ?? '').toString(),
    phone: (contact['waId'] ?? contact['phone']) as String?,
    messages: _newestFirst(
      ((j['messages'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(chatMessageFromJson)
          .toList(),
    ),
    // The API renames the engine's isDirectMessageDeliveryWindowOpened to
    // `windowOpen`, but passes conversationExpiresAt through verbatim.
    channel: MessageChannelX.fromApi(contact['channel'] ?? j['channel']),
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

/// Default page size the API documents for messages. Only used as the
/// last-resort "was this page full?" heuristic below.
const int _messagesPerPage = 50;

/// Whether an older page of messages exists.
///
/// Read tolerantly because the exact `messagesMeta` shape is documented but not
/// yet observed from a real token — an explicit flag is preferred, then
/// last-page and total/per-page arithmetic, and only then a guess from whether
/// this page came back full. Guessing wrong costs one request that returns
/// nothing; the alternative, hard-coding a shape that turns out different, is a
/// thread that silently refuses to page.
bool _hasMore(Map<String, dynamic> body, int page, int received) {
  final Map<String, dynamic>? meta =
      (body['messagesMeta'] ?? body['messages_meta'] ?? body['meta'])
          as Map<String, dynamic>?;

  if (meta != null) {
    final Object? explicit = meta['hasMore'] ?? meta['has_more'];
    if (explicit is bool) return explicit;

    final int lastPage = _int(meta['lastPage'] ?? meta['last_page']);
    if (lastPage > 0) return page < lastPage;

    final int total = _int(meta['total'] ?? meta['totalCount']);
    final int perPage = _int(meta['perPage'] ?? meta['per_page']);
    if (total > 0 && perPage > 0) return page * perPage < total;
  }

  // No usable meta: a short page means the end, a full one probably does not.
  return received >= _messagesPerPage;
}

/// Guarantees newest-first, whichever way the endpoint happened to sort.
///
/// The thread used to render upside down because two inversions stopped
/// cancelling: the mapper assumed oldest-first and the view applied `.reversed`
/// on top of a `reverse: true` list. When the API moved to newest-first
/// pagination the pair no longer cancelled, and nothing failed loudly — order
/// is not something a parser checks.
///
/// Detecting and reversing rather than sorting is deliberate: it is O(n), and
/// it leaves messages sharing a timestamp in exactly the order the server sent
/// them. A sort would be free to shuffle those, which shows up as two bubbles
/// swapping places between reloads.
List<ChatMessage> _newestFirst(List<ChatMessage> messages) {
  DateTime? first;
  DateTime? last;
  for (final ChatMessage m in messages) {
    if (m.sentAt == null) continue;
    first ??= m.sentAt;
    last = m.sentAt;
  }
  // Undated, single, or all-equal timestamps: nothing to infer, leave as sent.
  if (first == null || last == null || !first.isBefore(last)) return messages;
  return messages.reversed.toList();
}

ChatMessage chatMessageFromJson(Map<String, dynamic> j) {
  return ChatMessage(
    uid: (j['uid'] ?? '').toString(),
    body: MessageText.plain((j['body'] ?? j['message'] ?? '').toString()),
    isIncoming: (j['isIncoming'] as bool?) ?? false,
    // Absent on an older payload, which maps to text — present and unknown
    // maps to `unsupported`, so a new server-side type shows as something
    // rather than as a blank bubble.
    kind: MessageKindX.fromApi(j['type'] ?? j['messageType']),
    sentAt: _date(j['messagedAt']),
    status: j['status'] as String?,
    agentName: (j['agent'] ?? j['agent_name']) as String?,
    receivedOn: (j['receivedOn'] ?? j['received_on']) as String?,
    // All four keys are present on every message with the unused ones null,
    // so these parse to null rather than throwing on a plain text row.
    media: MessageMedia.fromJson(j['media']),
    interactive: MessageInteractive.fromJson(j['interactive']),
    template: MessageTemplate.fromJson(j['template']),
    order: MessageOrder.fromJson(j['order']),
    unsupportedReason: (j['unsupportedReason'] as String?)?.trim().isEmpty ?? true
        ? null
        : (j['unsupportedReason'] as String?),
    isBotReply: (j['isBotReply'] as bool?) ?? false,
    campaignName: (j['campaign'] is Map<String, dynamic>)
        ? (j['campaign'] as Map<String, dynamic>)['name'] as String?
        : j['campaign'] as String?,
  );
}

final conversationRepositoryProvider = Provider<ConversationRepository>(
  (Ref ref) => ConversationRepositoryImpl(ref.watch(apiClientProvider)),
);

/// Active inbox filter, shared between the chip bar and the list.
final inboxFilterProvider = StateProvider<InboxFilter>((Ref ref) => InboxFilter.all);

/// How often the inbox re-reads itself while it is on screen.
///
/// Slower than the chat poll: the inbox is a glance, not a conversation. Same
/// reason it exists at all — without a push channel, a new conversation never
/// appears and an unread count never moves until the tab is left and returned
/// to. Driven from the screen, for the reason on [kChatPollInterval].
const Duration kInboxPollInterval = Duration(seconds: 15);

final inboxListProvider =
    FutureProvider.autoDispose<List<Conversation>>((Ref ref) {
  final InboxFilter filter = ref.watch(inboxFilterProvider);
  return ref.watch(conversationRepositoryProvider).list(filter: filter);
});

/// The chat thread, paged.
///
/// A notifier rather than a `FutureProvider` because pages have to accumulate:
/// a FutureProvider can only replace its value, so every older page would
/// discard the one before it. This is the app's first paginated provider — the
/// other lists still load whole.
///
/// Exposes [ChatThreadController.loadOlder] for the scroll listener and
/// [ChatThreadController.reload] for pull-to-refresh and post-action refreshes.
final chatThreadProvider = AsyncNotifierProvider.autoDispose
    .family<ChatThreadController, ChatThread, String>(
  ChatThreadController.new,
);

/// How often an open thread re-reads its newest page.
///
/// There is no websocket and no push channel in this API, so a timer is the
/// only way a conversation stays live. Six seconds is a compromise: fast
/// enough that a reply feels like it arrived, slow enough that a thread left
/// open costs ten requests a minute rather than sixty.
///
/// The timer itself lives on the *screen*, not here. A provider does not know
/// when it is visible — something else can keep it alive — and autoDispose
/// runs a frame later, which leaves a timer ticking over a torn-down tree.
/// `State.dispose` is synchronous and exact.
const Duration kChatPollInterval = Duration(seconds: 6);

class ChatThreadController
    extends AutoDisposeFamilyAsyncNotifier<ChatThread, String> {
  /// Riverpod 2's Ref has no `mounted`, and a refresh in flight when the
  /// reader leaves would otherwise write to a disposed notifier.
  bool _gone = false;

  @override
  Future<ChatThread> build(String contactUid) {
    _gone = false;
    ref.onDispose(() => _gone = true);
    return ref.watch(conversationRepositoryProvider).thread(contactUid);
  }

  /// Fetches the next older page and appends it to the tail.
  ///
  /// Appending is why [ChatThread.messages] is newest-first: older messages go
  /// on the end, so nothing already rendered moves and the reversed list does
  /// not jump under the reader's thumb.
  Future<void> loadOlder() async {
    final ChatThread? current = state.valueOrNull;
    // The re-entry guard: a fast flick fires the scroll listener many times,
    // and without this each one would request the same page.
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncData<ChatThread>(current.copyWith(loadingMore: true));
    try {
      final ChatThread next = await ref
          .read(conversationRepositoryProvider)
          .thread(arg, page: current.page + 1);

      // Dedupe by uid: overlapping pages are a normal consequence of new
      // messages arriving between requests, and a duplicate key in a list this
      // long is a visible glitch rather than a crash.
      final Set<String> seen =
          current.messages.map((ChatMessage m) => m.uid).toSet();
      final List<ChatMessage> merged = <ChatMessage>[
        ...current.messages,
        ...next.messages.where((ChatMessage m) => !seen.contains(m.uid)),
      ];

      state = AsyncData<ChatThread>(current.copyWith(
        messages: merged,
        page: next.page,
        hasMore: next.hasMore,
        loadingMore: false,
      ));
    } catch (_) {
      // Keep what is already on screen; a failed older page should not empty
      // the thread. The caller surfaces the error.
      state = AsyncData<ChatThread>(current.copyWith(loadingMore: false));
      rethrow;
    }
  }

  /// Re-reads page 1, discarding accumulated pages.
  ///
  /// Deliberately NOT called after sending a message: that would throw away
  /// every older page the reader had scrolled back through, so the thread would
  /// collapse to 50 messages on each send. Use [prepend] for that.
  Future<void> reload() async {
    state = const AsyncLoading<ChatThread>();
    state = await AsyncValue.guard(
      () => ref.read(conversationRepositoryProvider).thread(arg),
    );
  }

  /// Puts a message at the head without refetching, preserving loaded pages.
  void prepend(ChatMessage message) {
    final ChatThread? current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData<ChatThread>(current.copyWith(
      messages: <ChatMessage>[message, ...current.messages],
    ));
  }

  /// Re-reads page 1 and folds anything new into what is already loaded.
  ///
  /// This is what makes the thread live. Three things it deliberately does not
  /// do, each of which is why [reload] cannot be used on a timer:
  ///
  /// * **No `AsyncLoading`.** This runs behind the reader's back every few
  ///   seconds; a spinner over a thread someone is reading is far worse than
  ///   the staleness it fixes.
  /// * **No page loss.** Older pages scrolled back through are kept — only the
  ///   newest page is re-read and merged.
  /// * **No pointless rebuilds.** When nothing has changed the state is left
  ///   alone, so a quiet conversation does not repaint on every tick.
  ///
  /// Messages already on screen are *replaced* by their fresh copies rather
  /// than skipped, because that is how a delivery tick moves from sent to
  /// delivered to read without a manual refresh.
  Future<void> refreshHead() async {
    final ChatThread? current = state.valueOrNull;
    // Nothing loaded yet, or a load already in flight — `build` will deliver.
    if (current == null || current.loadingMore) return;

    final ChatThread head;
    try {
      head = await ref.read(conversationRepositoryProvider).thread(arg);
    } catch (_) {
      // A poll that fails is not an error state: the thread on screen is still
      // valid and the next tick will try again. Surfacing this would replace a
      // readable conversation with a retry button because one request timed
      // out, which is the opposite of the point.
      return;
    }
    if (_gone) return;

    final Set<String> known = <String>{
      for (final ChatMessage m in current.messages) m.uid,
    };
    final List<ChatMessage> fresh = <ChatMessage>[
      for (final ChatMessage m in head.messages)
        if (!known.contains(m.uid)) m,
    ];

    final Map<String, ChatMessage> byUid = <String, ChatMessage>{
      for (final ChatMessage m in head.messages) m.uid: m,
    };
    final List<ChatMessage> merged = <ChatMessage>[
      ...fresh,
      for (final ChatMessage m in current.messages) byUid[m.uid] ?? m,
    ];

    // Cheap change detection: a new message, a status that moved, or the
    // service window opening or closing. Anything else and this tick is a
    // no-op.
    final bool statusMoved = current.messages.any(
      (ChatMessage m) => byUid[m.uid] != null && byUid[m.uid]!.status != m.status,
    );
    if (fresh.isEmpty &&
        !statusMoved &&
        head.windowOpen == current.windowOpen) {
      return;
    }

    state = AsyncData<ChatThread>(current.copyWith(
      messages: merged,
      windowOpen: head.windowOpen,
      windowExpiresAt: head.windowExpiresAt,
    ));
  }
}

/// The reply lock for one conversation.
///
/// autoDispose because it is only meaningful while a chat is on screen, and
/// family because two chats can be open across a back-stack.
///
/// Deliberately NOT polled. The hold is five minutes and
/// [ReplyLock.atNow] expires it locally, which covers the common case at no
/// cost; a timer against this API would add a request per chat per interval to
/// a server that has already been seen saturating its FPM pool. It refreshes
/// when the chat opens, after a takeover, and on pull-to-refresh.
final replyLockProvider =
    FutureProvider.autoDispose.family<ReplyLock, String>((Ref ref, String uid) {
  return ref.watch(conversationRepositoryProvider).replyLock(uid);
});
