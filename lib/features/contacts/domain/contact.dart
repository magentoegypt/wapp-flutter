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
  final bool isBlocked;
}

/// Dropdown data for the Add-contact form, fetched in one call so the form
/// doesn't fan out to four endpoints on open.
class ContactMeta {
  const ContactMeta({
    this.groups = const <NamedRef>[],
    this.labels = const <NamedRef>[],
    this.countries = const <NamedRef>[],
  });

  final List<NamedRef> groups;
  final List<NamedRef> labels;
  final List<NamedRef> countries;

  static const ContactMeta empty = ContactMeta();
}

class NamedRef {
  const NamedRef({required this.id, required this.name});

  final String id;
  final String name;
}
