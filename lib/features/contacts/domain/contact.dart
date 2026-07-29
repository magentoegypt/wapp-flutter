/// A customer record. `wa_id` on the backend is the WhatsApp phone identifier
/// and doubles as the conversation key, which is why [phone] is required.
class Contact {
  const Contact({
    required this.uid,
    required this.name,
    required this.phone,
    this.email,
    this.countryCode,
    this.labels = const <String>[],
    this.groups = const <String>[],
    this.lastSeenAt,
    this.isBlocked = false,
  });

  final String uid;
  final String name;
  final String phone;
  final String? email;
  final String? countryCode;
  final List<String> labels;
  final List<String> groups;
  final DateTime? lastSeenAt;
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
