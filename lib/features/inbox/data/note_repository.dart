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

/// The note's author, however the payload spells them.
///
/// `author` is an **object**, not a string. `.toString()` on it printed the
/// whole map into the author line — every note card read
/// `{uid: d57867fa-65f8-4e6…` and the avatar took its initials from the brace,
/// so the column showed `{C` and `{A`. A string is still accepted, because the
/// create response and the list have been seen to differ.
String _authorName(Object? raw) {
  if (raw is Map) {
    final Object? name = raw['name'] ?? raw['fullName'];
    if (name != null && '$name'.trim().isNotEmpty) return '$name'.trim();
    final String composed = <String>[
      '${raw['firstName'] ?? ''}'.trim(),
      '${raw['lastName'] ?? ''}'.trim(),
    ].where((String s) => s.isNotEmpty).join(' ');
    if (composed.isNotEmpty) return composed;
    // An email is a worse label than a name but a far better one than a uid.
    final Object? email = raw['email'];
    return email == null ? '' : '$email'.trim();
  }
  return '${raw ?? ''}'.trim();
}

InternalNote noteFromJson(Map<String, dynamic> j) {
  return InternalNote(
    uid: (j['uid'] ?? j['_uid'] ?? '').toString(),
    body: (j['message'] ?? j['body'] ?? '').toString(),
    authorName: _authorName(
      j['author'] ?? j['author_name'] ?? j['user'] ?? j['createdBy'],
    ),
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
