import '../../inbox/domain/channel.dart';

/// Where a contact sits in the sales lifecycle.
///
/// The frames segment the Contacts list by these three (278:2) and print the
/// stage as a pill in every row's trailing slot, so it is display data as much
/// as filter data.
enum LifecycleStage {
  customer,
  lead,
  vip;

  /// Null for an absent or unrecognised value.
  ///
  /// The backend serialises the stage into the same `status` string that
  /// carries `blocked`, and nothing guarantees the vocabulary — returning null
  /// keeps an unknown slug out of the UI instead of printing it raw or
  /// defaulting everyone to "customer".
  static LifecycleStage? fromApi(Object? raw) {
    final String value = '${raw ?? ''}'.trim().toLowerCase();
    for (final LifecycleStage stage in values) {
      if (stage.name == value) return stage;
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
    this.groups = const <String>[],
    this.lifecycleStage,
    this.createdAt,
    this.isBlocked = false,
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
  final List<String> groups;

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
}

/// Dropdown data for the Add-contact form, fetched in one call so the form
/// doesn't fan out to four endpoints on open.
class ContactMeta {
  const ContactMeta({
    this.groups = const <NamedRef>[],
    this.labels = const <NamedRef>[],
    this.countries = const <NamedRef>[],
    this.customFields = const <CustomField>[],
  });

  final List<NamedRef> groups;
  final List<NamedRef> labels;
  final List<NamedRef> countries;

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
