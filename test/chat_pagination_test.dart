import 'package:clickalize/core/util/message_text.dart';
import 'package:clickalize/features/inbox/data/conversation_repository.dart';
import 'package:clickalize/features/inbox/domain/conversation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pagination cover for the chat thread — the app's first paginated provider.
///
/// The failure modes worth pinning are all silent ones: pages replacing instead
/// of accumulating, a fling firing the same request repeatedly, overlapping
/// pages rendering a message twice, and a send collapsing the loaded history
/// back to one page.
ChatMessage _m(String uid, int hourAgo) => ChatMessage(
      uid: uid,
      body: MessageText.plain(uid),
      isIncoming: true,
      sentAt: DateTime(2026, 7, 30, 23 - hourAgo),
    );

class _FakeRepo implements ConversationRepository {
  _FakeRepo(this.pages);

  /// page number -> the messages that page returns
  final Map<int, List<ChatMessage>> pages;
  final List<int> requested = <int>[];

  @override
  Future<ChatThread> thread(String contactUid, {int page = 1}) async {
    requested.add(page);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return ChatThread(
      contactUid: contactUid,
      name: 'Amira',
      messages: pages[page] ?? const <ChatMessage>[],
      windowOpen: true,
      page: page,
      hasMore: pages.containsKey(page + 1),
    );
  }

  @override
  Future<List<Conversation>> list({
    InboxFilter filter = InboxFilter.all,
    String? query,
  }) async =>
      const <Conversation>[];
  @override
  Future<void> sendMessage(String contactUid, String body) async {}
  @override
  Future<void> setStatus(String contactUid, ConversationStatus status) async {}
  @override
  Future<int> unreadCount() async => 0;
}

/// Container with a standing subscription to the thread.
///
/// The provider is `autoDispose`. Without a listener it is torn down the moment
/// each `read` returns, so the next `read` rebuilds and refetches page 1 — the
/// test would measure disposal, not paging. A widget always holds it in the
/// real app; this is the equivalent.
ProviderContainer _containerFor(_FakeRepo repo, String uid) {
  final ProviderContainer c = ProviderContainer(
    overrides: <Override>[
      conversationRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(c.dispose);
  c.listen<AsyncValue<ChatThread>>(
    chatThreadProvider(uid),
    (AsyncValue<ChatThread>? _, AsyncValue<ChatThread> __) {},
    fireImmediately: true,
  );
  return c;
}

void main() {
  test('loadOlder appends the next page to the tail, newest stays first',
      () async {
    final _FakeRepo repo = _FakeRepo(<int, List<ChatMessage>>{
      1: <ChatMessage>[_m('n1', 0), _m('n2', 1)],
      2: <ChatMessage>[_m('o1', 2), _m('o2', 3)],
    });
    final ProviderContainer c = _containerFor(repo, 'c1');

    await c.read(chatThreadProvider('c1').future);
    await c.read(chatThreadProvider('c1').notifier).loadOlder();

    final ChatThread t = c.read(chatThreadProvider('c1')).requireValue;
    expect(t.messages.map((ChatMessage m) => m.uid),
        <String>['n1', 'n2', 'o1', 'o2']);
    expect(t.messages.first.uid, 'n1', reason: 'newest must stay at index 0');
    expect(t.page, 2);
    expect(t.hasMore, isFalse);
  });

  test('loadOlder stops once hasMore is false', () async {
    final _FakeRepo repo = _FakeRepo(<int, List<ChatMessage>>{
      1: <ChatMessage>[_m('n1', 0)],
    });
    final ProviderContainer c = _containerFor(repo, 'c1');

    await c.read(chatThreadProvider('c1').future);
    await c.read(chatThreadProvider('c1').notifier).loadOlder();
    await c.read(chatThreadProvider('c1').notifier).loadOlder();

    expect(repo.requested, <int>[1], reason: 'must not ask past the end');
  });

  test('concurrent loadOlder calls issue only one request', () async {
    final _FakeRepo repo = _FakeRepo(<int, List<ChatMessage>>{
      1: <ChatMessage>[_m('n1', 0)],
      2: <ChatMessage>[_m('o1', 1)],
      3: <ChatMessage>[_m('o2', 2)],
    });
    final ProviderContainer c = _containerFor(repo, 'c1');
    await c.read(chatThreadProvider('c1').future);

    // A fling fires the scroll notification on every frame.
    final ChatThreadController n = c.read(chatThreadProvider('c1').notifier);
    await Future.wait(<Future<void>>[n.loadOlder(), n.loadOlder(), n.loadOlder()]);

    expect(repo.requested, <int>[1, 2],
        reason: 're-entry guard must collapse the burst to one page');
  });

  test('overlapping pages do not render a message twice', () async {
    final _FakeRepo repo = _FakeRepo(<int, List<ChatMessage>>{
      1: <ChatMessage>[_m('a', 0), _m('b', 1)],
      // `b` repeats because a new message arrived between requests.
      2: <ChatMessage>[_m('b', 1), _m('c', 2)],
    });
    final ProviderContainer c = _containerFor(repo, 'c1');

    await c.read(chatThreadProvider('c1').future);
    await c.read(chatThreadProvider('c1').notifier).loadOlder();

    final ChatThread t = c.read(chatThreadProvider('c1')).requireValue;
    expect(t.messages.map((ChatMessage m) => m.uid), <String>['a', 'b', 'c']);
  });

  test('prepend keeps the loaded pages instead of collapsing to page 1',
      () async {
    final _FakeRepo repo = _FakeRepo(<int, List<ChatMessage>>{
      1: <ChatMessage>[_m('n1', 1)],
      2: <ChatMessage>[_m('o1', 2)],
    });
    final ProviderContainer c = _containerFor(repo, 'c1');

    await c.read(chatThreadProvider('c1').future);
    await c.read(chatThreadProvider('c1').notifier).loadOlder();
    c.read(chatThreadProvider('c1').notifier).prepend(_m('sent', 0));

    final ChatThread t = c.read(chatThreadProvider('c1')).requireValue;
    expect(t.messages.map((ChatMessage m) => m.uid),
        <String>['sent', 'n1', 'o1']);
    expect(repo.requested, <int>[1, 2], reason: 'prepend must not refetch');
  });
}
