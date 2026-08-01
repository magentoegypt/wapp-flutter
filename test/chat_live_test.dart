import 'package:clickalize/core/util/message_text.dart';
import 'package:clickalize/features/inbox/data/conversation_repository.dart';
import 'package:clickalize/features/inbox/domain/conversation.dart';
import 'package:clickalize/features/inbox/domain/reply_lock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The thread has to stay live without a websocket.
///
/// Before this, nothing refreshed: an incoming reply never appeared, and a
/// message you sent often did not either — `_send` called `reload()`, which
/// re-reads page 1 and races the server, so the send returned before the
/// message was readable and the re-read came back without it. Leaving the
/// conversation and re-entering was the only way to see either, which is
/// exactly what was reported.
///
/// `reload()` is the wrong tool on a timer for three separate reasons, and
/// each is pinned below: it blanks the thread to a spinner, it discards every
/// older page, and it cannot update a delivery tick in place.
ChatMessage _m(String uid, {String? status, bool incoming = false}) =>
    ChatMessage(
      uid: uid,
      body: MessageText.plain(uid),
      isIncoming: incoming,
      sentAt: DateTime(2026, 8, 1, 12),
      status: status,
    );

class _FakeRepo implements ConversationRepository {
  _FakeRepo(this.head, {this.older = const <ChatMessage>[]});

  /// What page 1 answers with. Reassign between calls to simulate the server
  /// moving on.
  List<ChatMessage> head;
  List<ChatMessage> older;
  bool windowOpen = true;
  int threadCalls = 0;
  bool throwNext = false;

  @override
  Future<ChatThread> thread(String contactUid, {int page = 1}) async {
    threadCalls++;
    if (throwNext) throw Exception('network');
    return ChatThread(
      contactUid: contactUid,
      name: 'Amira',
      messages: page == 1 ? head : older,
      windowOpen: windowOpen,
      page: page,
      hasMore: page == 1 && older.isNotEmpty,
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
  @override
  Future<ReplyLock> replyLock(String contactUid) async => ReplyLock.free;
  @override
  Future<ReplyLock> takeoverReplyLock(String contactUid) async => ReplyLock.free;
}

Future<(ProviderContainer, _FakeRepo)> _open(_FakeRepo repo) async {
  final ProviderContainer c = ProviderContainer(
    overrides: <Override>[
      conversationRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(c.dispose);
  // A standing listener, so autoDispose does not tear the notifier down
  // between awaits.
  c.listen(chatThreadProvider('c1'), (_, __) {}, fireImmediately: true);
  await c.read(chatThreadProvider('c1').future);
  return (c, repo);
}

void main() {
  test('a new message arrives without leaving the conversation', () async {
    final (ProviderContainer c, _FakeRepo repo) =
        await _open(_FakeRepo(<ChatMessage>[_m('m2'), _m('m1')]));

    // The customer replies.
    repo.head = <ChatMessage>[_m('m3', incoming: true), _m('m2'), _m('m1')];
    await c.read(chatThreadProvider('c1').notifier).refreshHead();

    final ChatThread t = c.read(chatThreadProvider('c1')).value!;
    // Newest first, so the new one is at the head and nothing else moved.
    expect(t.messages.map((ChatMessage m) => m.uid), <String>['m3', 'm2', 'm1']);
  });

  test('older pages survive a refresh', () async {
    final _FakeRepo repo = _FakeRepo(
      <ChatMessage>[_m('m2'), _m('m1')],
      older: <ChatMessage>[_m('m0')],
    );
    final (ProviderContainer c, _) = await _open(repo);

    await c.read(chatThreadProvider('c1').notifier).loadOlder();
    expect(
      c.read(chatThreadProvider('c1')).value!.messages.length,
      3,
      reason: 'page 2 loaded',
    );

    repo.head = <ChatMessage>[_m('m3'), _m('m2'), _m('m1')];
    await c.read(chatThreadProvider('c1').notifier).refreshHead();

    // This is what `reload()` destroyed: scrolling back through a long history
    // and then having it collapse to the newest page.
    expect(
      c.read(chatThreadProvider('c1')).value!.messages.map((ChatMessage m) => m.uid),
      <String>['m3', 'm2', 'm1', 'm0'],
    );
  });

  test('a delivery tick moves without a reload', () async {
    final _FakeRepo repo = _FakeRepo(<ChatMessage>[_m('m1', status: 'sent')]);
    final (ProviderContainer c, _) = await _open(repo);

    repo.head = <ChatMessage>[_m('m1', status: 'read')];
    await c.read(chatThreadProvider('c1').notifier).refreshHead();

    // Merging only unseen uids would leave this at 'sent' forever.
    expect(c.read(chatThreadProvider('c1')).value!.messages.single.status, 'read');
  });

  test('the thread never blanks to a spinner while refreshing', () async {
    final (ProviderContainer c, _FakeRepo repo) =
        await _open(_FakeRepo(<ChatMessage>[_m('m1')]));

    repo.head = <ChatMessage>[_m('m2'), _m('m1')];
    final Future<void> pending =
        c.read(chatThreadProvider('c1').notifier).refreshHead();

    // Mid-flight the reader must still see their conversation. `reload()` sets
    // AsyncLoading here, which is a spinner over a thread every six seconds.
    expect(c.read(chatThreadProvider('c1')).hasValue, isTrue);
    expect(c.read(chatThreadProvider('c1')).isLoading, isFalse);
    await pending;
  });

  test('a failed poll leaves the conversation readable', () async {
    final (ProviderContainer c, _FakeRepo repo) =
        await _open(_FakeRepo(<ChatMessage>[_m('m1')]));

    // Nothing here should turn a working screen into a retry button.
    repo.throwNext = true;
    await c.read(chatThreadProvider('c1').notifier).refreshHead();

    expect(c.read(chatThreadProvider('c1')).hasError, isFalse);
    expect(
      c.read(chatThreadProvider('c1')).value!.messages.single.uid,
      'm1',
      reason: 'the conversation is still on screen',
    );
  });

  test('the service window closing is picked up', () async {
    final (ProviderContainer c, _FakeRepo repo) =
        await _open(_FakeRepo(<ChatMessage>[_m('m1')]));
    expect(c.read(chatThreadProvider('c1')).value!.windowOpen, isTrue);

    repo.windowOpen = false;
    await c.read(chatThreadProvider('c1').notifier).refreshHead();

    // The 24-hour window can lapse while the thread is open. A banner still
    // counting down an hour after it shut is worse than no banner.
    expect(c.read(chatThreadProvider('c1')).value!.windowOpen, isFalse);
  });

  test('a quiet conversation does not rebuild on every tick', () async {
    final (ProviderContainer c, _FakeRepo repo) =
        await _open(_FakeRepo(<ChatMessage>[_m('m1')]));
    final ChatThread before = c.read(chatThreadProvider('c1')).value!;

    await c.read(chatThreadProvider('c1').notifier).refreshHead();

    // Same instance: nothing changed, so no new state was written and no
    // widget repainted.
    expect(identical(c.read(chatThreadProvider('c1')).value, before), isTrue);
  });
}
