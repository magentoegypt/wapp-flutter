import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

/// A canned reply. `__data.template` on the backend holds the body, which is
/// why [body] is read from a nested key when present.
class QuickReply {
  const QuickReply({
    required this.uid,
    required this.title,
    required this.body,
    this.category,
    this.language = 'en',
    this.active = true,
  });

  final String uid;
  final String title;
  final String body;

  /// Grouping the list's filter chips and the editor's select share. Null on a
  /// record that has never been categorised — the frames' chip row is derived
  /// from the categories actually in use, so an uncategorised library simply
  /// shows no chips rather than empty buckets.
  final String? category;

  final String language;
  final bool active;
}

/// The category ids the editor offers.
///
/// Kept as plain strings rather than an enum because the value round-trips
/// through the API: a category the backend already holds that is not in this
/// list still survives an edit instead of being silently reset.
abstract final class QuickReplyCategories {
  static const String greetings = 'greetings';
  static const String orders = 'orders';
  static const String support = 'support';

  /// Presentation order, matching the frame's chip row.
  static const List<String> known = <String>[greetings, orders, support];
}

abstract interface class QuickReplyRepository {
  Future<List<QuickReply>> list();
  Future<QuickReply> byUid(String uid);
  Future<void> create({
    required String title,
    required String body,
    String? category,
  });
  Future<void> update(
    String uid, {
    required String title,
    required String body,
    String? category,
  });
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
  Future<void> create({
    required String title,
    required String body,
    String? category,
  }) =>
      _api.post('/quick-replies', body: <String, dynamic>{
        'title': title,
        'template': body,
        // Sent even when null: on update this is the only way to clear a
        // category the record already carries.
        'category': category,
      });

  @override
  Future<void> update(
    String uid, {
    required String title,
    required String body,
    String? category,
  }) =>
      _api.put('/quick-replies/$uid', body: <String, dynamic>{
        'title': title,
        'template': body,
        'category': category,
      });

  @override
  Future<void> remove(String uid) => _api.delete('/quick-replies/$uid');
}

QuickReply quickReplyFromJson(Map<String, dynamic> j) {
  // Blank and absent are the same thing here — an empty string would otherwise
  // become a nameless filter chip.
  final String category = (j['category'] ?? '').toString().trim();

  return QuickReply(
    uid: (j['uid'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    body: (j['body'] ?? j['template'] ?? '').toString(),
    category: category.isEmpty ? null : category,
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
