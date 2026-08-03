import '../../inbox/domain/channel.dart';

/// Where a contact sits in the lifecycle, as the backend actually models it.
///
/// The frame (278:2) segments Contacts by **Customer / Lead / VIP** and prints
/// one of those as a pill on every row. That taxonomy does not exist in this
/// API. Every contact carries `customerType`, whose entire observed vocabulary
/// across the workspace is `new` and `returning` — there is no `status` field
/// at all, which is what the stage used to be read from.
///
/// So the pill was permanently absent: a column the frame fills on every row
/// rendered empty on all of them, and no amount of data would have changed it.
/// Matching the backend's own two values makes it real. Departing from the
/// frame here is deliberate — inventing Lead and VIP client-side would put a
/// label on a contact that nothing in the system supports.
enum LifecycleStage {
  /// `new` on the wire. Not spelled `new` here — it is a Dart reserved word.
  newCustomer('new'),
  returning('returning');

  const LifecycleStage(this.wire);

  final String wire;

  /// Null for an absent or unrecognised value.
  ///
  /// Nothing guarantees the vocabulary, so an unknown slug maps to null rather
  /// than being printed raw or defaulting everyone to one bucket.
  static LifecycleStage? fromApi(Object? raw) {
    final String value = '${raw ?? ''}'.trim().toLowerCase();
    for (final LifecycleStage stage in values) {
      if (stage.wire == value) return stage;
    }
    return null;
  }
}

/// A customer record. `wa_id` on the backend is the WhatsApp phone identifier
/// and doubles as the conversation key, which is why [phone] is required.
class Contact {
  const Contact({
    required this.uid,
    required this.name,
    required this.phone,
    this.email,
    this.countryCode,
    this.city,
    this.language,
    this.labels = const <String>[],
    this.groups = const <NamedRef>[],
    this.lifecycleStage,
    this.createdAt,
    this.isBlocked = false,
    this.isFavorite = false,
    this.channel = MessageChannel.whatsapp,
    this.instagramUsername,
  });

  final String uid;
  final String name;
  final String phone;
  final String? email;
  final String? countryCode;
  final String? city;
  final String? language;
  final List<String> labels;

  /// Carries the uid, not just the display name.
  ///
  /// `POST /contacts/{uid}/groups/{groupUid}/remove` needs the group's uid, and
  /// this list used to be flattened to names on the way in — so the endpoint
  /// was not merely unwired, it was **uncallable**. [NamedRef] is the type the
  /// rest of the contacts feature already uses for exactly this pair.
  final List<NamedRef> groups;

  /// Null when the payload carried no recognised stage — the detail and list
  /// screens then omit the pill rather than guess one.
  final LifecycleStage? lifecycleStage;

  final DateTime? createdAt;

  /// WhatsApp or Instagram. Defaulted server-side, so it is never null on the
  /// wire — the default here only covers a payload from before it was sent.
  final MessageChannel channel;

  /// Populated on Instagram contacts only.
  ///
  /// Worth carrying because [phone] on an Instagram contact is not a phone
  /// number: `waId` holds the IGSID, a 16-digit account id that means nothing
  /// to an agent and reads as a malformed number next to real ones.
  final String? instagramUsername;

  /// What to show under the name. The IGSID is never it.
  String? get subtitleLine {
    if (channel.isInstagram) {
      final String? u = instagramUsername?.trim();
      return (u == null || u.isEmpty) ? null : (u.startsWith('@') ? u : '@$u');
    }
    return phone.isEmpty ? null : phone;
  }
  final bool isBlocked;

  /// `favorite`. Real data the app used to discard entirely — every contact
  /// carries it and it is the only per-contact flag the workspace actually
  /// sets. Shown as a star beside the name; not editable, because no endpoint
  /// in the checkout toggles it.
  final bool isFavorite;
}

/// Dropdown data for the Add-contact form, fetched in one call so the form
/// doesn't fan out to four endpoints on open.
class ContactMeta {
  const ContactMeta({
    this.groups = const <GroupRef>[],
    this.labels = const <NamedRef>[],
    this.countries = const <CountryRef>[],
    this.customFields = const <CustomField>[],
  });

  /// Carries both identifiers — see [GroupRef] for why that is not redundant.
  final List<GroupRef> groups;
  final List<NamedRef> labels;

  /// 252 rows, carrying their dialling codes — see [CountryRef] for why the
  /// dialling code is worth keeping rather than reducing these to [NamedRef].
  final List<CountryRef> countries;

  /// Per-workspace extra fields. The form renders this list — never a
  /// hard-coded set, because the definitions differ per vendor and two of this
  /// workspace's eight are required.
  final List<CustomField> customFields;

  static const ContactMeta empty = ContactMeta();
}

/// A vendor-defined contact field.
///
/// [NamedRef] cannot stand in for this: it carries only an id and a name, and
/// rendering the right input needs the type, whether it is required, and the
/// options for a dropdown.
class CustomField {
  const CustomField({
    required this.uid,
    required this.name,
    this.type = 'text',
    this.required = false,
    this.options = const <String>[],
  });

  final String uid;
  final String name;

  /// The console's own vocabulary: text, number, url, datetime-local, dropdown.
  final String type;

  /// Enforced by the console form, NOT by the API — `store()` forwards custom
  /// fields without validating them, so a contact created without a required
  /// one is accepted. The client has to enforce it or the data quietly rots.
  final bool required;

  final List<String> options;

  bool get isDropdown => type.toLowerCase() == 'dropdown';
  bool get isNumber => type.toLowerCase() == 'number';
  bool get isUrl => type.toLowerCase() == 'url';
  bool get isDateTime => type.toLowerCase().startsWith('datetime');
}

class NamedRef {
  const NamedRef({required this.id, required this.name});

  final String id;
  final String name;
}

/// A contact group, which needs **both** of its identifiers.
///
/// The API is not consistent about which one it wants, and the inconsistency is
/// invisible from the client because every endpoint accepts the string and then
/// simply matches nothing:
///
///   * `contact_groups` on contact create/update is resolved with
///     `whereIn('_id', …)` — **numeric id**.
///   * `POST /contacts/{uid}/groups/{groupUid}/remove` and the campaign
///     audience take the **uid**.
///
/// Sending a uid where an id is wanted silently assigns no groups. On *update*
/// it is worse than silent: the engine computes the removal set as
/// `array_diff(existingIds, sentValues)`, so a list of uids matches none of the
/// existing ids and every group the contact had is dropped.
///
/// Keeping both here means the call site picks deliberately rather than
/// inheriting whichever one [NamedRef] happened to prefer.
class GroupRef {
  const GroupRef({required this.uid, required this.id, required this.name});

  /// For the remove endpoint and the campaign audience.
  final String uid;

  /// For `contact_groups` on create and update.
  final String id;

  final String name;
}

/// A country, kept richer than [NamedRef] because of the phone rule.
///
/// `POST /contacts` validates `phone_number` as
/// `numeric|min_digits:9|doesnt_start_with:+,0` — so the one format the Figma
/// frame shows in its own placeholder, `+20 100 234 5678`, is rejected by the
/// server three times over: the `+`, the spaces, and the leading zero a user
/// naturally types after the dialling code.
///
/// Carrying [phoneCode] lets the form show the selected country's code beside
/// the field and explain the rule in advance, instead of letting the user
/// discover it as a 422 after they press Save.
class CountryRef {
  const CountryRef({
    required this.id,
    required this.name,
    this.isoCode = '',
    this.phoneCode = '',
  });

  /// The numeric `_id`; this is what `country` expects on create, not the ISO
  /// code the field's old name implied.
  final String id;
  final String name;
  final String isoCode;

  /// Digits only, no `+` — e.g. "20". Empty when the row has none.
  final String phoneCode;
}
