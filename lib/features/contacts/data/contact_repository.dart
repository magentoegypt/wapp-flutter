import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../inbox/domain/channel.dart';
import '../domain/contact.dart';

abstract interface class ContactRepository {
  Future<List<Contact>> list({String? query});
  Future<Contact> byUid(String uid);
  Future<ContactMeta> meta();
  /// Create a contact.
  ///
  /// The body is **snake_case**, the same as [update] — `POST /contacts`
  /// validates `first_name`, `last_name`, `phone_number`, `email`, `country`,
  /// `language_code`, `contact_city`, `contact_tags` and `contact_groups`.
  ///
  /// It previously sent `name`, `phone` and `groups`: three keys the endpoint
  /// does not read. Because `first_name` and `phone_number` are both
  /// `required`, the request failed validation before it ever reached the
  /// engine, so **Add contact could not create anyone**. It failed loudly with
  /// a 422 rather than silently, which is the only reason it is a bug and not
  /// a data-corruption incident — but the message named fields the form did
  /// not show, so the error read as nonsense.
  Future<Contact> create({
    required String firstName,
    String? lastName,
    required String phoneNumber,
    String? email,
    String? countryId,
    String? languageCode,
    String? city,
    String? tags,
    List<String> groupIds,
    Map<String, String> customFields,
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
    return contactMetaFromJson(
      (body as Map<String, dynamic>?) ?? const <String, dynamic>{},
    );
  }

  @override
  Future<Contact> create({
    required String firstName,
    String? lastName,
    required String phoneNumber,
    String? email,
    String? countryId,
    String? languageCode,
    String? city,
    String? tags,
    List<String> groupIds = const <String>[],
    Map<String, String> customFields = const <String, String>{},
  }) async {
    // Optional strings are omitted when blank rather than sent as "". `email`
    // is validated as `nullable|email`, so an empty string is not "no email" to
    // this endpoint — it is an invalid one, and would 422 a form the user left
    // untouched.
    final dynamic body = await _api.post(
      '/contacts',
      body: buildCreateBody(
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
        email: email,
        countryId: countryId,
        languageCode: languageCode,
        city: city,
        tags: tags,
        groupIds: groupIds,
        customFields: customFields,
      ),
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

}

/// Vendor-defined fields from `/contacts/meta`.
///
/// Kept separate from [_sharedRefs] because these carry a type, a required flag
/// and options, none of which [NamedRef] can hold — and it is the type that
/// decides whether the form shows a text box, a number pad or a dropdown.
List<CustomField> _sharedCustomFields(dynamic raw) {
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

/// Contact groups, keeping both identifiers.
///
/// `/contacts/meta` returns `{uid, id, title}` for each. The shared ref helper
/// prefers `uid`, and `contact_groups` on create/update is matched by numeric
/// `_id` — so routing groups through it assigned nothing, and on update removed
/// everything. See [GroupRef].
List<GroupRef> _sharedGroups(dynamic raw) {
  if (raw is! List) return const <GroupRef>[];
  return raw
      .whereType<Map<String, dynamic>>()
      .map((Map<String, dynamic> e) => GroupRef(
            uid: (e['uid'] ?? '').toString(),
            id: (e['id'] ?? '').toString(),
            name: (e['title'] ?? e['name'] ?? '').toString(),
          ))
      .where((GroupRef g) => g.id.isNotEmpty || g.uid.isNotEmpty)
      .toList();
}

List<NamedRef> _sharedRefs(dynamic raw) {
  if (raw is! List) return const <NamedRef>[];
  return raw
      .whereType<Map<String, dynamic>>()
      .map((Map<String, dynamic> e) => NamedRef(
            id: (e['uid'] ?? e['id'] ?? '').toString(),
            name: (e['title'] ?? e['name'] ?? '').toString(),
          ))
      .toList();
}

/// Countries keep their own shape.
///
/// ⚠ `id` here is the numeric `_id`, **not** `uid` — the countries list is the
/// one entry in `/contacts/meta` that carries no uid, and `country` on create
/// expects that id. Running these through [_sharedRefs], which prefers `uid`,
/// would have produced empty ids and a dropdown that submitted nothing.
///
/// Rows missing an id or a name are dropped rather than shown, because a
/// country you can select but not submit is worse than one that is absent.
List<CountryRef> _sharedCountries(dynamic raw) {
  if (raw is! List) return const <CountryRef>[];
  return raw
      .whereType<Map<String, dynamic>>()
      .map((Map<String, dynamic> e) => CountryRef(
            id: (e['id'] ?? '').toString(),
            name: (e['name'] ?? '').toString(),
            isoCode: (e['isoCode'] ?? '').toString(),
            phoneCode: (e['phoneCode'] ?? '').toString(),
          ))
      .where((CountryRef c) => c.id.isNotEmpty && c.name.isNotEmpty)
      .toList();
}

/// The `POST /contacts` request body.
///
/// Split out from [ContactRepositoryImpl.create] so the wire keys can be
/// asserted directly. They are the part that was wrong — the screen and the
/// mapper were both fine — and the part no other test covers.
///
/// Blank optionals are dropped rather than sent as `""`, because the server's
/// `nullable|email` rule treats an empty string as an invalid address, not as
/// an absent one. The two `required` fields are always present, never behind a
/// conditional.
Map<String, dynamic> buildCreateBody({
  required String firstName,
  String? lastName,
  required String phoneNumber,
  String? email,
  String? countryId,
  String? languageCode,
  String? city,
  String? tags,
  List<String> groupIds = const <String>[],
  Map<String, String> customFields = const <String, String>{},
}) {
  bool has(String? v) => v != null && v.isNotEmpty;

  return <String, dynamic>{
    'first_name': firstName,
    if (has(lastName)) 'last_name': lastName,
    'phone_number': phoneNumber,
    if (has(email)) 'email': email,
    if (has(countryId)) 'country': countryId,
    if (has(languageCode)) 'language_code': languageCode,
    if (has(city)) 'contact_city': city,
    if (has(tags)) 'contact_tags': tags,
    // Numeric group ids, not uids — the engine resolves these with
    // whereIn('_id', …). See GroupRef.
    if (groupIds.isNotEmpty) 'contact_groups': groupIds,
    // Keyed by field uid: custom_input_fields[<uid>] = value. The create path
    // does consume these — `processContactCreate` reads them and writes the
    // values — so a workspace with required custom fields can be filled in
    // properly from the app rather than left to be completed in the console.
    if (customFields.isNotEmpty) 'custom_input_fields': customFields,
  };
}

/// `/contacts/meta`, flat under the envelope — no singular record key.
///
/// Carries 252 countries as of the 30 Jul API pass; it previously returned
/// none, which is why the Add-contact country field was left out rather than
/// shipped against an empty list.
ContactMeta contactMetaFromJson(Map<String, dynamic> j) => ContactMeta(
      groups: _sharedGroups(j['groups']),
      labels: _sharedRefs(j['labels']),
      countries: _sharedCountries(j['countries']),
      customFields: _sharedCustomFields(j['customFields'] ?? j['custom_fields']),
    );

/// The contact's city, wherever the serialiser put it.
///
/// It is not a column. `storeContactContext()` writes it into the contact's
/// `__data` JSON blob under **both** `contact_city` and `city`, and the
/// detailed shape lifts it to a top-level `city`. Each of those is tried in
/// turn, including the raw blob under its `_data`/`__data` spellings, because
/// a value that exists but is read under the wrong name renders as an absent
/// row — indistinguishable from a contact who has no city.
String? _city(Map<String, dynamic> j) {
  String? clean(Object? v) {
    final String s = '${v ?? ''}'.trim();
    return s.isEmpty ? null : s;
  }

  final String? direct = clean(j['city'] ?? j['contactCity'] ?? j['contact_city']);
  if (direct != null) return direct;

  final Object? blob = j['__data'] ?? j['_data'] ?? j['data'];
  if (blob is Map) {
    return clean(blob['contact_city'] ?? blob['city']);
  }
  return null;
}

/// The contact's filled-in custom field values.
///
/// `value` is whatever string the field was answered with — the API stores
/// custom values untyped, so a NUMBER field comes back as text and is rendered
/// as text rather than being coerced into something it may not be.
List<ContactCustomValue> _values(Object? raw) {
  if (raw is! List) return const <ContactCustomValue>[];
  final List<ContactCustomValue> out = <ContactCustomValue>[];
  for (final Object? e in raw) {
    if (e is! Map) continue;
    final String name = '${e['name'] ?? ''}'.trim();
    final String value = '${e['value'] ?? ''}'.trim();
    // A field with no answer is not worth a row; a field with no name cannot
    // be labelled, so neither is shown.
    if (name.isEmpty || value.isEmpty) continue;
    out.add(ContactCustomValue(
      fieldUid: '${e['uid'] ?? ''}',
      name: name,
      value: value,
    ));
  }
  return out;
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
    // City does not live in a column — the server keeps it inside the
    // contact's `__data` JSON blob and surfaces it as `city` only on the
    // detailed read. Every spelling that blob is known to use is accepted, and
    // the blob itself is read as a last resort, so a serialiser change cannot
    // blank the row silently.
    city: _city(j),
    language: (j['language'] ?? j['languageCode']) as String?,
    labels: strings(j['labels']),
    groups: refs(j['groups']),
    customFields: _values(j['customFields'] ?? j['custom_fields']),
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
