/// The four payload blocks a message can carry.
///
/// Exactly one is non-null, and all four are null for plain text. They are
/// present as keys on every message, so absence is a null value rather than a
/// missing key — which is why every reader here tolerates both.
///
/// The parsers are deliberately forgiving in one specific way: the API returns
/// `""` rather than null for `headerText`, `footerText` and `mediaLink` on many
/// rows. An empty string that reaches the UI as "present" renders as blank
/// header space, which looks like a broken bubble rather than an absent field.
/// [_str] collapses the two.
library;

/// Trimmed, or null when absent *or* empty.
String? _str(Object? v) {
  if (v is! String) return null;
  final String s = v.trim();
  return s.isEmpty ? null : s;
}

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// Rows of a list-valued key, skipping anything that is not a map.
List<Map<String, dynamic>> _rows(Object? v) => v is List
    ? v.whereType<Map<String, dynamic>>().toList(growable: false)
    : const <Map<String, dynamic>>[];

// ---- Media ------------------------------------------------------------------

/// Image, video, audio or document.
class MessageMedia {
  const MessageMedia({
    this.link,
    this.fileName,
    this.caption,
    this.mimeType,
    this.sizeBytes,
    this.sourceKind,
  });

  /// `mediaLink`. Frequently `""`, and null here when it is.
  final String? link;

  /// The customer-facing name. Never `storedFileName`, which is the on-disk
  /// name and means nothing to an agent.
  final String? fileName;

  final String? caption;
  final String? mimeType;
  final int? sizeBytes;

  /// Meta's raw spelling, kept for the Instagram case where a document arrives
  /// as `file` and is normalised to `document` on the way out.
  final String? sourceKind;

  static MessageMedia? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    return MessageMedia(
      link: _str(raw['mediaLink'] ?? raw['link'] ?? raw['url']),
      fileName: _str(raw['fileName'] ?? raw['name']),
      caption: _str(raw['caption']),
      mimeType: _str(raw['mimeType'] ?? raw['type']),
      sizeBytes: _int(raw['size'] ?? raw['fileSize']),
      sourceKind: _str(raw['sourceKind']),
    );
  }

  /// Rendered as "1.2 MB". Null rather than "0 B" when the size is unknown,
  /// because a confident zero reads as an empty file.
  String? get readableSize {
    final int? b = sizeBytes;
    if (b == null || b <= 0) return null;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ---- Interactive ------------------------------------------------------------

/// A reply button. The API flattens Meta's 1-indexed object to a list.
class InteractiveButton {
  const InteractiveButton({required this.title, this.id});

  final String title;
  final String? id;

  static InteractiveButton? fromJson(Map<String, dynamic> j) {
    final String? t = _str(j['title'] ?? j['text']);
    return t == null ? null : InteractiveButton(title: t, id: _str(j['id']));
  }
}

class ListRow {
  const ListRow({required this.title, this.description, this.id});

  final String title;
  final String? description;
  final String? id;

  static ListRow? fromJson(Map<String, dynamic> j) {
    final String? t = _str(j['title']);
    return t == null
        ? null
        : ListRow(
            title: t,
            description: _str(j['description']),
            id: _str(j['id'] ?? j['rowId']),
          );
  }
}

class ListSection {
  const ListSection({required this.title, required this.rows});

  final String? title;
  final List<ListRow> rows;

  static ListSection fromJson(Map<String, dynamic> j) => ListSection(
        title: _str(j['title']),
        rows: _rows(j['rows'])
            .map(ListRow.fromJson)
            .whereType<ListRow>()
            .toList(growable: false),
      );
}

class CtaUrl {
  const CtaUrl({required this.url, this.displayText});

  final String url;
  final String? displayText;

  static CtaUrl? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final String? u = _str(raw['url']);
    return u == null ? null : CtaUrl(url: u, displayText: _str(raw['displayText']));
  }
}

class MessageLocation {
  const MessageLocation({this.name, this.address, this.latitude, this.longitude});

  final String? name;
  final String? address;
  final double? latitude;
  final double? longitude;

  static MessageLocation? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    return MessageLocation(
      name: _str(raw['name']),
      address: _str(raw['address']),
      latitude: _num(raw['lat'] ?? raw['latitude']),
      longitude: _num(raw['lng'] ?? raw['longitude']),
    );
  }

  bool get hasPoint => latitude != null && longitude != null;
}

class ContactCard {
  const ContactCard({
    required this.name,
    this.phones = const <String>[],
    this.emails = const <String>[],
  });

  final String name;
  final List<String> phones;
  final List<String> emails;

  /// Meta nests the display name under `name.formatted_name`, but the API has
  /// been seen to flatten it; both are read rather than guessed at.
  static ContactCard? fromJson(Map<String, dynamic> j) {
    final Object? n = j['name'];
    final String? name = _str(
      n is Map<String, dynamic> ? (n['formatted_name'] ?? n['formattedName']) : n,
    );
    if (name == null) return null;

    List<String> pluck(Object? list, String key) => _rows(list)
        .map((Map<String, dynamic> e) => _str(e[key]))
        .whereType<String>()
        .toList(growable: false);

    return ContactCard(
      name: name,
      phones: pluck(j['phones'], 'phone'),
      emails: pluck(j['emails'], 'email'),
    );
  }
}

class CatalogRef {
  const CatalogRef({this.catalogId, this.thumbnailProductRetailerId});

  /// Absent on 18 of the 29 live catalog messages, so the bubble must render
  /// without it rather than assuming it is there.
  final String? catalogId;
  final String? thumbnailProductRetailerId;

  static CatalogRef? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    return CatalogRef(
      catalogId: _str(raw['catalogId'] ?? raw['id']),
      thumbnailProductRetailerId: _str(raw['thumbnailProductRetailerId']),
    );
  }
}

class ProductRef {
  const ProductRef({required this.retailerId, this.section});

  final String retailerId;

  /// Set on multi-product messages, which group by it.
  final String? section;

  static ProductRef? fromJson(Map<String, dynamic> j) {
    final String? id = _str(j['retailerId'] ?? j['productRetailerId'] ?? j['id']);
    return id == null
        ? null
        : ProductRef(retailerId: id, section: _str(j['section']));
  }
}

/// Everything under `interactive`.
///
/// One object rather than a union because the API sends one shape with the
/// unused branches null — modelling it as a sealed hierarchy would mean
/// choosing a variant from the message `type`, which is exactly the key
/// sniffing the contract says not to do.
class MessageInteractive {
  const MessageInteractive({
    this.headerText,
    this.footerText,
    this.buttons = const <InteractiveButton>[],
    this.listSections = const <ListSection>[],
    this.listButtonText,
    this.ctaUrl,
    this.location,
    this.contacts = const <ContactCard>[],
    this.catalog,
    this.products = const <ProductRef>[],
  });

  final String? headerText;
  final String? footerText;
  final List<InteractiveButton> buttons;
  final List<ListSection> listSections;
  final String? listButtonText;
  final CtaUrl? ctaUrl;
  final MessageLocation? location;
  final List<ContactCard> contacts;
  final CatalogRef? catalog;
  final List<ProductRef> products;

  static MessageInteractive? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    return MessageInteractive(
      headerText: _str(raw['headerText']),
      footerText: _str(raw['footerText']),
      buttons: _rows(raw['buttons'])
          .map(InteractiveButton.fromJson)
          .whereType<InteractiveButton>()
          .toList(growable: false),
      listSections:
          _rows(raw['listSections']).map(ListSection.fromJson).toList(growable: false),
      listButtonText: _str(raw['listButtonText']),
      ctaUrl: CtaUrl.fromJson(raw['ctaUrl']),
      location: MessageLocation.fromJson(raw['location']),
      contacts: _rows(raw['contacts'])
          .map(ContactCard.fromJson)
          .whereType<ContactCard>()
          .toList(growable: false),
      catalog: CatalogRef.fromJson(raw['catalog']),
      products: _rows(raw['products'])
          .map(ProductRef.fromJson)
          .whereType<ProductRef>()
          .toList(growable: false),
    );
  }

  /// Rows across every section, for the count shown on the collapsed bubble.
  int get listRowCount =>
      listSections.fold(0, (int n, ListSection s) => n + s.rows.length);
}

// ---- Template ---------------------------------------------------------------

/// A button inside a template's BUTTONS component.
///
/// `type` is Meta's uppercase spelling. Only the seven seen live are given
/// meaning; anything else still renders with its text rather than vanishing.
class TemplateButton {
  const TemplateButton({required this.type, required this.text, this.value});

  final String type;
  final String text;

  /// The URL, phone number or code, depending on [type].
  final String? value;

  static TemplateButton? fromJson(Map<String, dynamic> j) {
    final String? t = _str(j['text'] ?? j['title']);
    if (t == null) return null;
    return TemplateButton(
      type: (_str(j['type']) ?? 'QUICK_REPLY').toUpperCase(),
      text: t,
      value: _str(j['url'] ?? j['phoneNumber'] ?? j['phone_number'] ?? j['couponCode']),
    );
  }
}

/// One component of a template message.
class TemplateComponent {
  const TemplateComponent({
    required this.type,
    this.format,
    this.text,
    this.buttons = const <TemplateButton>[],
  });

  /// `BODY` · `HEADER` · `FOOTER` · `BUTTONS` · `CAROUSEL`.
  final String type;

  /// For a HEADER: `TEXT`, `IMAGE` or `PRODUCT`.
  final String? format;

  final String? text;
  final List<TemplateButton> buttons;

  static TemplateComponent fromJson(Map<String, dynamic> j) => TemplateComponent(
        type: (_str(j['type']) ?? '').toUpperCase(),
        format: _str(j['format'])?.toUpperCase(),
        text: _str(j['text']),
        buttons: _rows(j['buttons'])
            .map(TemplateButton.fromJson)
            .whereType<TemplateButton>()
            .toList(growable: false),
      );
}

class MessageTemplate {
  const MessageTemplate({
    this.name,
    this.category,
    this.components = const <TemplateComponent>[],
  });

  final String? name;

  /// `MARKETING` or `UTILITY` on this install. AUTHENTICATION never occurs.
  final String? category;

  final List<TemplateComponent> components;

  static MessageTemplate? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    return MessageTemplate(
      name: _str(raw['name']),
      category: _str(raw['category'])?.toUpperCase(),
      components: _rows(raw['components'])
          .map(TemplateComponent.fromJson)
          .toList(growable: false),
    );
  }

  TemplateComponent? _first(bool Function(TemplateComponent) test) {
    for (final TemplateComponent c in components) {
      if (test(c)) return c;
    }
    return null;
  }

  TemplateComponent? get header => _first((TemplateComponent c) => c.type == 'HEADER');
  TemplateComponent? get body => _first((TemplateComponent c) => c.type == 'BODY');
  TemplateComponent? get footer => _first((TemplateComponent c) => c.type == 'FOOTER');

  List<TemplateButton> get buttons =>
      _first((TemplateComponent c) => c.type == 'BUTTONS')?.buttons ??
      const <TemplateButton>[];
}

// ---- Order ------------------------------------------------------------------

class OrderItem {
  const OrderItem({
    required this.name,
    this.quantity,
    this.unitPrice,
    this.lineTotal,
    this.currency,
    this.retailerId,
  });

  final String name;
  final int? quantity;
  final double? unitPrice;
  final double? lineTotal;
  final String? currency;
  final String? retailerId;

  static OrderItem fromJson(Map<String, dynamic> j) => OrderItem(
        // Catalog items can arrive without a name; the retailer id is the only
        // other handle an agent has on which product this is.
        name: _str(j['name'] ?? j['productName']) ??
            _str(j['retailerId'] ?? j['productRetailerId']) ??
            '',
        quantity: _int(j['quantity']),
        unitPrice: _num(j['unitPrice']),
        lineTotal: _num(j['lineTotal']),
        currency: _str(j['currency']),
        retailerId: _str(j['retailerId'] ?? j['productRetailerId']),
      );
}

/// An inbound cart the customer sent from the catalog.
///
/// These arrived as blank bubbles until the API started recovering them: they
/// are stored with `message` NULL and the payload only ever existed inside the
/// raw Meta webhook, which is stripped on the way out.
class MessageOrder {
  const MessageOrder({
    this.items = const <OrderItem>[],
    this.itemCount,
    this.currency,
    this.total,
  });

  final List<OrderItem> items;
  final int? itemCount;
  final String? currency;

  /// Null when the cart mixes currencies. Show the lines rather than a sum
  /// that would be wrong — adding SAR to USD silently produces a number that
  /// looks authoritative and is not.
  final double? total;

  static MessageOrder? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    return MessageOrder(
      items: _rows(raw['items']).map(OrderItem.fromJson).toList(growable: false),
      itemCount: _int(raw['itemCount']),
      currency: _str(raw['currency']),
      total: _num(raw['total']),
    );
  }

  /// Prefer the server's count; fall back to the lines actually present.
  int get count => itemCount ?? items.length;

  /// True when the server withheld a total. Distinct from a zero total.
  bool get isMixedCurrency => total == null && items.isNotEmpty;
}
