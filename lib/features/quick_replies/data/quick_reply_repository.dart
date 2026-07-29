import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

/// A canned reply. `__data.template` on the backend holds the body, which is
/// why [body] is read from a nested key when present.
class QuickReply {
  const QuickReply({
    required this.uid,
    required this.title,
    required this.body,
    this.language = 'en',
    this.active = true,
  });

  final String uid;
  final String title;
  final String body;
  final String language;
  final bool active;
}

abstract interface class QuickReplyRepository {
  Future<List<QuickReply>> list();
  Future<QuickReply> byUid(String uid);
  Future<void> create({required String title, required String body});
  Future<void> update(String uid, {required String title, required String body});
  Future<void> remove(String uid);
}

class QuickReplyRepositoryImpl implements QuickReplyRepository {
  const QuickReplyRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<List<QuickReply>> list() async {
    final dynamic body = await _api.get('/quick-replies');
    if (body is List) {
      return body.whereType<Map<String, dynamic>>().map(quickReplyFromJson).toList();
    }
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final List<dynamic> rows =
        (m['quickReplies'] ?? m['data']) as List<dynamic>? ?? const <dynamic>[];
    return rows.whereType<Map<String, dynamic>>().map(quickReplyFromJson).toList();
  }

  @override
  Future<QuickReply> byUid(String uid) async {
    final dynamic body = await _api.get('/quick-replies/$uid');
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    // Singular domain key, not `data`.
    return quickReplyFromJson((m['quickReply'] as Map<String, dynamic>?) ??
        (m['data'] as Map<String, dynamic>?) ??
        m);
  }

  @override
  Future<void> create({required String title, required String body}) =>
      _api.post('/quick-replies',
          body: <String, dynamic>{'title': title, 'template': body});

  @override
  Future<void> update(String uid, {required String title, required String body}) =>
      _api.put('/quick-replies/$uid',
          body: <String, dynamic>{'title': title, 'template': body});

  @override
  Future<void> remove(String uid) => _api.delete('/quick-replies/$uid');
}

QuickReply quickReplyFromJson(Map<String, dynamic> j) {
  return QuickReply(
    uid: (j['uid'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    body: (j['body'] ?? j['template'] ?? '').toString(),
    language: (j['language'] ?? 'en').toString(),
    // The API exposes a boolean `active`, not the raw integer status column.
    active: (j['active'] as bool?) ?? true,
  );
}

final quickReplyRepositoryProvider = Provider<QuickReplyRepository>(
  (Ref ref) => QuickReplyRepositoryImpl(ref.watch(apiClientProvider)),
);

final quickReplyListProvider =
    FutureProvider.autoDispose<List<QuickReply>>((Ref ref) {
  return ref.watch(quickReplyRepositoryProvider).list();
});

final quickReplyDetailProvider =
    FutureProvider.autoDispose.family<QuickReply, String>((Ref ref, String uid) {
  return ref.watch(quickReplyRepositoryProvider).byUid(uid);
});
