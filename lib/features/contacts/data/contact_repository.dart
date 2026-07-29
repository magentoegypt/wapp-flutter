import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/contact.dart';

abstract interface class ContactRepository {
  Future<List<Contact>> list({String? query});
  Future<Contact> byUid(String uid);
  Future<ContactMeta> meta();
  Future<Contact> create({
    required String name,
    required String phone,
    String? email,
    List<String> groupIds,
  });
}

class ContactRepositoryImpl implements ContactRepository {
  const ContactRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<List<Contact>> list({String? query}) async {
    final dynamic body = await _api.get(
      '/contacts',
      query: <String, dynamic>{
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
    return _rows(body).map(contactFromJson).toList();
  }

  @override
  Future<Contact> byUid(String uid) async {
    final dynamic body = await _api.get('/contacts/$uid');
    return contactFromJson(_unwrap(body));
  }

  @override
  Future<ContactMeta> meta() async {
    final dynamic body = await _api.get('/contacts/meta');
    final Map<String, dynamic> j = _unwrap(body);
    return ContactMeta(
      groups: _refs(j['groups']),
      labels: _refs(j['labels']),
      countries: _refs(j['countries']),
    );
  }

  @override
  Future<Contact> create({
    required String name,
    required String phone,
    String? email,
    List<String> groupIds = const <String>[],
  }) async {
    final dynamic body = await _api.post(
      '/contacts',
      body: <String, dynamic>{
        'name': name,
        'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (groupIds.isNotEmpty) 'groups': groupIds,
      },
    );
    return contactFromJson(_unwrap(body));
  }

  List<Map<String, dynamic>> _rows(dynamic body) {
    final List<dynamic> raw = body is List
        ? body
        : ((body as Map<String, dynamic>)['data'] as List<dynamic>? ??
            const <dynamic>[]);
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  Map<String, dynamic> _unwrap(dynamic body) {
    final Map<String, dynamic> m = (body as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    // Laravel resources wrap single records in `data`.
    return (m['data'] as Map<String, dynamic>?) ?? m;
  }

  List<NamedRef> _refs(dynamic raw) {
    if (raw is! List) return const <NamedRef>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> e) => NamedRef(
              id: (e['id'] ?? e['uid'] ?? '').toString(),
              name: (e['name'] ?? e['title'] ?? '').toString(),
            ))
        .toList();
  }
}

Contact contactFromJson(Map<String, dynamic> j) {
  List<String> strings(Object? v) => v is List
      ? v
          .map((dynamic e) => e is Map ? (e['name'] ?? e['title'] ?? '').toString() : e.toString())
          .where((String s) => s.isNotEmpty)
          .toList()
      : const <String>[];

  return Contact(
    uid: (j['uid'] ?? j['_uid'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    phone: (j['phone'] ?? j['wa_id'] ?? '').toString(),
    email: j['email'] as String?,
    countryCode: (j['countryCode'] ?? j['country_code']) as String?,
    labels: strings(j['labels']),
    groups: strings(j['groups']),
    lastSeenAt:
        DateTime.tryParse('${j['lastSeenAt'] ?? j['last_seen_at'] ?? ''}')?.toLocal(),
    isBlocked: (j['status'] as num?)?.toInt() == 3,
  );
}

final contactRepositoryProvider = Provider<ContactRepository>(
  (Ref ref) => ContactRepositoryImpl(ref.watch(apiClientProvider)),
);

final contactSearchProvider = StateProvider<String>((Ref ref) => '');

final contactListProvider = FutureProvider.autoDispose<List<Contact>>((Ref ref) {
  final String q = ref.watch(contactSearchProvider);
  return ref.watch(contactRepositoryProvider).list(query: q);
});

final contactDetailProvider =
    FutureProvider.autoDispose.family<Contact, String>((Ref ref, String uid) {
  return ref.watch(contactRepositoryProvider).byUid(uid);
});

final contactMetaProvider = FutureProvider.autoDispose<ContactMeta>((Ref ref) {
  return ref.watch(contactRepositoryProvider).meta();
});
