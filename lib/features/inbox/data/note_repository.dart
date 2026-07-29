import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/internal_note.dart';

abstract interface class NoteRepository {
  Future<List<InternalNote>> list(String contactUid);
  Future<void> add(String contactUid, String body);
  Future<void> update(String noteUid, String body);
  Future<void> remove(String noteUid);
}

class NoteRepositoryImpl implements NoteRepository {
  const NoteRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<List<InternalNote>> list(String contactUid) async {
    final dynamic body = await _api.get('/contacts/$contactUid/notes');
    if (body is List) {
      return body.whereType<Map<String, dynamic>>().map(noteFromJson).toList();
    }
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final List<dynamic> rows =
        (m['notes'] ?? m['data']) as List<dynamic>? ?? const <dynamic>[];
    return rows.whereType<Map<String, dynamic>>().map(noteFromJson).toList();
  }

  @override
  Future<void> add(String contactUid, String body) =>
      _api.post('/contacts/$contactUid/notes',
          body: <String, dynamic>{'message': body});

  @override
  Future<void> update(String noteUid, String body) =>
      _api.put('/notes/$noteUid', body: <String, dynamic>{'message': body});

  @override
  Future<void> remove(String noteUid) => _api.delete('/notes/$noteUid');
}

InternalNote noteFromJson(Map<String, dynamic> j) {
  return InternalNote(
    uid: (j['uid'] ?? j['_uid'] ?? '').toString(),
    body: (j['message'] ?? j['body'] ?? '').toString(),
    authorName: (j['author'] ?? j['author_name'] ?? '').toString(),
    createdAt: DateTime.tryParse('${j['createdAt'] ?? j['created_at'] ?? ''}')
        ?.toLocal(),
    edited: (j['edited'] as bool?) ?? (j['edited'] as num?) == 1,
  );
}

final noteRepositoryProvider = Provider<NoteRepository>(
  (Ref ref) => NoteRepositoryImpl(ref.watch(apiClientProvider)),
);

final notesProvider = FutureProvider.autoDispose
    .family<List<InternalNote>, String>((Ref ref, String contactUid) {
  return ref.watch(noteRepositoryProvider).list(contactUid);
});
