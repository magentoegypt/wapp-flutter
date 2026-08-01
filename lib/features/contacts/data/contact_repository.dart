import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../inbox/domain/channel.dart';
import '../domain/contact.dart';

abstract interface class ContactRepository {
  Future<List<Contact>> list({String? query});
  Future<Contact> byUid(String uid);
  Future<ContactMeta> meta();
  Future<Contact> create({
    required String name,
    required String phone,
    String? email,
    String? countryCode,
    List<String> groupIds,
  });

  /// Partial update — unsent fields are preserved server-side, so a screen may
  /// send only what it changed.
  ///
  /// The body is **snake_case**, unlike every other write in this app, with
  /// `enableAiBot` as the one camelCase exception. That is the API's shape, not
  /// a transcription slip.
  Future<Contact> update(
    String uid, {
    String? firstName,
    String? lastName,
    String? email,
    String? languageCode,
    String? city,
    List<String>? tags,
    List<String>? groupIds,
    bool? enableAiBot,
    Map<String, String>? customFields,
  });

  /// Removes the contact from the workspace.
  ///
  /// The API separately refuses the campaign test contact, so a failure here is
  /// not always a permission problem — surface the server's own wording.
  Future<void> delete(String uid);

  /// Takes the contact out of one group. Needs the group's **uid**, which is
  /// why [Contact.groups] carries [NamedRef] rather than plain names.
  Future<void> removeFromGroup(String uid, String groupUid);

  /// Uploads an xlsx workbook of contacts.
  ///
  /// Deliberately not routed through `/media/upload`: that endpoint keys its
  /// restrictions on `whatsapp_<type>` and would accept every Office format
  /// Meta allows. This one validates `mimes:xlsx` under the console's own
  /// import key.
  Future<String> import(String filePath, String fileName);

  /// Downloads the contact workbook. Returns the bytes; the caller decides
  /// where they land.
  Future<List<int>> export({String? type});
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
  Future<void> delete(String uid) => _api.delete('/contacts/$uid');

  @override
  Future<void> removeFromGroup(String uid, String groupUid) =>
      _api.post('/contacts/$uid/groups/$groupUid/remove');

  @override
  Future<String> import(String filePath, String fileName) async {
    final dynamic body = await _api.post(
      '/contacts/import',
      body: FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      }),
      // A workbook of several thousand rows is parsed synchronously server
      // side; the client's 20s JSON default aborts that partway and reports a
      // timeout for an import that was still running.
      timeout: const Duration(minutes: 3),
    );
    return body is Map<String, dynamic>
        ? '${body['message'] ?? ''}'
        : '';
  }

  @override
  Future<List<int>> export({String? type}) => _api.bytes(
        '/contacts/export',
        query: <String, dynamic>{if (type != null) 'type': type},
      );

  @override
  Future<Contact> byUid(String uid) async {
    final dynamic body = await _api.get('/contacts/$uid');
    return contactFromJson(_record(body, 'contact'));
  }

  @override
  Future<ContactMeta> meta() async {
    final dynamic body = await _api.get('/contacts/meta');
    // meta is flat under the envelope - no singular record key.
    final Map<String, dynamic> j =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    // `/contacts/meta` carries 252 countries as of the 30 Jul API pass; it
    // previously returned none, which is why the Add-contact country field was
    // left out rather than shipped against an empty list.
    return ContactMeta(
      groups: _refs(j['groups']),
      labels: _refs(j['labels']),
      countries: _refs(j['countries']),
      customFields: _customFields(j['customFields'] ?? j['custom_fields']),
    );
  }

  @override
  Future<Contact> create({
    required String name,
    required String phone,
    String? email,
    String? countryCode,
    List<String> groupIds = const <String>[],
  }) async {
    final dynamic body = await _api.post(
      '/contacts',
      body: <String, dynamic>{
        'name': name,
        'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (countryCode != null && countryCode.isNotEmpty) 'country': countryCode,
        if (groupIds.isNotEmpty) 'groups': groupIds,
      },
    );
    return contactFromJson(_record(body, 'contact'));
  }

  @override
  Future<Contact> update(
    String uid, {
    String? firstName,
    String? lastName,
    String? email,
    String? languageCode,
    String? city,
    List<String>? tags,
    List<String>? groupIds,
    bool? enableAiBot,
    Map<String, String>? customFields,
  }) async {
    // Only non-null values are sent. The endpoint is partial-safe, so omitting
    // a key preserves it — but sending an explicit null clears it, which is how
    // a sibling endpoint silently wiped an agent's role, team and manager when
    // a caller passed only one field. Building the map this way makes "not
    // supplied" and "cleared" different things at the call site.
    final Map<String, dynamic> payload = <String, dynamic>{
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (email != null) 'email': email,
      if (languageCode != null) 'language_code': languageCode,
      if (city != null) 'contact_city': city,
      if (tags != null) 'contact_tags': tags,
      if (groupIds != null) 'contact_groups': groupIds,
      // The one camelCase key in an otherwise snake_case body.
      if (enableAiBot != null) 'enableAiBot': enableAiBot,
      // Keyed by field uid: custom_input_fields[<uid>] = value.
      if (customFields != null && customFields.isNotEmpty)
        'custom_input_fields': customFields,
    };

    final dynamic body = await _api.put('/contacts/$uid', body: payload);
    return contactFromJson(_record(body, 'contact'));
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

  /// Single records nest under a singular domain key - `contact`, not
  /// `data`. Falls back to `data` and then the bare body so an envelope
  /// change degrades instead of rendering an empty screen.
  Map<String, dynamic> _record(dynamic body, String key) {
    final Map<String, dynamic> m =
        (body as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return (m[key] as Map<String, dynamic>?) ??
        (m['data'] as Map<String, dynamic>?) ??
        m;
  }

  /// Vendor-defined fields from `/contacts/meta`.
  ///
  /// Kept separate from [_refs] because these carry a type, a required flag and
  /// options, none of which [NamedRef] can hold — and it is the type that
  /// decides whether the form shows a text box, a number pad or a dropdown.
  List<CustomField> _customFields(dynamic raw) {
    final List<dynamic> list = (raw as List<dynamic>?) ?? const <dynamic>[];
    return list.whereType<Map<String, dynamic>>().map((Map<String, dynamic> j) {
      final List<dynamic> opts =
          (j['options'] ?? j['values']) as List<dynamic>? ?? const <dynamic>[];
      return CustomField(
        uid: '${j['uid'] ?? j['id'] ?? ''}',
        name: '${j['name'] ?? j['title'] ?? ''}',
        type: '${j['type'] ?? 'text'}',
        required: (j['required'] as bool?) ?? false,
        options: opts.map((dynamic o) => '$o').toList(),
      );
    }).where((CustomField f) => f.uid.isNotEmpty).toList();
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

  /// Groups keep their uid; labels stay names, having no endpoint that needs one.
  List<NamedRef> refs(Object? v) => v is List
      ? v
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> e) => NamedRef(
                id: '${e['uid'] ?? e['id'] ?? ''}',
                name: '${e['name'] ?? e['title'] ?? ''}',
              ))
          .where((NamedRef r) => r.name.isNotEmpty)
          .toList(growable: false)
      : const <NamedRef>[];

  return Contact(
    uid: (j['uid'] ?? '').toString(),
    name: (j['name'] ?? j['waId'] ?? '').toString(),
    // `waId` is the WhatsApp identifier and the conversation key; `phone` is
    // the display form and may be absent.
    phone: (j['phone'] ?? j['waId'] ?? '').toString(),
    email: j['email'] as String?,
    countryCode: (j['country'] ?? j['countryCode']) as String?,
    city: j['city'] as String?,
    language: (j['language'] ?? j['languageCode']) as String?,
    labels: strings(j['labels']),
    groups: refs(j['groups']),
    // `customerType`, not `status`. There is no `status` field on a contact —
    // reading one meant the stage was null on every row in the workspace and
    // the pill never rendered. An unrecognised value still maps to null.
    lifecycleStage: LifecycleStage.fromApi(j['customerType']),
    createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}')?.toLocal(),
    // Kept tolerant: no list row has ever carried `blocked`, but the detail
    // endpoint is a different serialiser and the flag matters when it is there.
    isBlocked: j['blocked'] == true ||
        j['isBlocked'] == true ||
        '${j['status'] ?? ''}' == 'blocked',
    isFavorite: j['favorite'] == true || j['isFavorite'] == true,
    channel: MessageChannelX.fromApi(j['channel']),
    instagramUsername: j['instagramUsername'] as String?,
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
