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
    // `/contacts/meta` returns groups, labels, customFields and
    // assignableUsers. There is no country list, so that stays empty.
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

  /// The API nests the list under a domain-named key (`contacts`), not
  /// `data`. Falls back so an envelope change doesn't silently empty the list.
  List<Map<String, dynamic>> _rows(dynamic body) {
    if (body is List) return body.whereType<Map<String, dynamic>>().toList();
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final List<dynamic> raw =
        (m['contacts'] ?? m['data']) as List<dynamic>? ?? const <dynamic>[];
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
              id: (e['uid'] ?? e['id'] ?? '').toString(),
              name: (e['title'] ?? e['name'] ?? '').toString(),
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
    uid: (j['uid'] ?? '').toString(),
    name: (j['name'] ?? j['waId'] ?? '').toString(),
    // `waId` is the WhatsApp identifier and the conversation key; `phone` is
    // the display form and may be absent.
    phone: (j['phone'] ?? j['waId'] ?? '').toString(),
    email: j['email'] as String?,
    countryCode: (j['country'] ?? j['countryCode']) as String?,
    labels: strings(j['labels']),
    groups: strings(j['groups']),
    lastSeenAt: DateTime.tryParse('${j['createdAt'] ?? ''}')?.toLocal(),
    isBlocked: '${j['status'] ?? ''}' == 'blocked',
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
