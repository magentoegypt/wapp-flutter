/// A WhatsApp message template, as the workspace manages it.
///
/// Distinct from the two `MessageTemplate` types already in this app: one is
/// the send-picker's view of a template's derived fields, the other is a
/// template *message* in a chat bubble. This is the editable record.
///
/// Every limit here was read from `WhatsAppTemplateController`'s validation
/// rules rather than from the handoff prose, which lists none of them.
library;

/// Meta's caps. Over-long values are rejected, not trimmed — unlike the
/// Instagram profile, where silence is the failure mode.
abstract final class WaTemplateLimits {
  static const int name = 512;
  static const int language = 15;
  static const int body = 1024;
  static const int footer = 60;

  /// A TEXT header, which is a different field from the body.
  static const int headerText = 60;

  static const int buttonText = 25;
  static const int buttonUrl = 2000;
}

/// Where Meta has got to with this template.
///
/// A template is not usable until Meta approves it, and approval is
/// asynchronous — which is the whole reason `POST /templates/sync` exists.
enum WaTemplateStatus { pending, approved, rejected, disabled, unknown }

extension WaTemplateStatusX on WaTemplateStatus {
  static WaTemplateStatus fromApi(Object? raw) {
    switch ('${raw ?? ''}'.trim().toLowerCase()) {
      case 'approved':
        return WaTemplateStatus.approved;
      case 'pending':
      case 'in_review':
      case 'submitted':
        return WaTemplateStatus.pending;
      case 'rejected':
        return WaTemplateStatus.rejected;
      case 'disabled':
      case 'paused':
        return WaTemplateStatus.disabled;
      default:
        return WaTemplateStatus.unknown;
    }
  }

  /// Only an approved template can actually be sent.
  bool get isSendable => this == WaTemplateStatus.approved;
}

/// The two categories that occur on this install.
///
/// Meta also allows AUTHENTICATION, and the API accepts it, but no template on
/// this workspace uses one — an OTP template needs a copy-code button and a
/// fixed body Meta supplies, which is a different editor. Offering it here
/// would present a form that cannot produce a valid authentication template.
enum WaTemplateCategory { marketing, utility }

extension WaTemplateCategoryX on WaTemplateCategory {
  String get wire => this == WaTemplateCategory.marketing
      ? 'MARKETING'
      : 'UTILITY';

  static WaTemplateCategory fromApi(Object? raw) =>
      '${raw ?? ''}'.trim().toUpperCase() == 'MARKETING'
          ? WaTemplateCategory.marketing
          : WaTemplateCategory.utility;
}

/// What sits above the body.
///
/// `image`, `video` and `document` are accepted by the API but need
/// `uploaded_media_file_name` — a file put through `/media/upload` first. Those
/// are 4 and 3 rows respectively on this install against 34 TEXT headers, and
/// the upload contract for a *template* header is not the same call the
/// composer makes, so they are deliberately not offered here yet rather than
/// guessed at. `location` and `product` likewise.
enum WaHeaderKind { none, text }

extension WaHeaderKindX on WaHeaderKind {
  /// Absent rather than empty: the server branches on the key being present.
  String? get wire => this == WaHeaderKind.text ? 'text' : null;
}

/// The button types this editor offers.
///
/// Meta defines more — COPY_CODE and DYNAMIC_URL_BUTTON both need an
/// `example` that must be alpha-dash, and VOICE_CALL is not configurable from
/// the console either. These three cover every button on this workspace.
enum WaButtonType { quickReply, phoneNumber, url }

extension WaButtonTypeX on WaButtonType {
  String get wire => switch (this) {
        WaButtonType.quickReply => 'QUICK_REPLY',
        WaButtonType.phoneNumber => 'PHONE_NUMBER',
        WaButtonType.url => 'URL_BUTTON',
      };

  static WaButtonType fromApi(Object? raw) {
    switch ('${raw ?? ''}'.trim().toUpperCase()) {
      case 'PHONE_NUMBER':
        return WaButtonType.phoneNumber;
      case 'URL_BUTTON':
      case 'URL':
      case 'DYNAMIC_URL_BUTTON':
        return WaButtonType.url;
      default:
        return WaButtonType.quickReply;
    }
  }
}

class WaButton {
  const WaButton({required this.type, required this.text, this.value});

  final WaButtonType type;

  /// ≤ 25 characters, and required for all three offered types.
  final String text;

  /// The URL or the phone number, depending on [type]. Null for a quick reply.
  final String? value;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type.wire,
        'text': text,
        // The server validates these per type, so only the one that belongs is
        // sent — a phone number under `url` fails the `url` rule and reads as
        // a mangled link rather than as the wrong field.
        if (type == WaButtonType.url) 'url': value,
        if (type == WaButtonType.phoneNumber) 'phone_number': value,
      };

  static WaButton? fromJson(Map<String, dynamic> j) {
    final String text = '${j['text'] ?? j['title'] ?? ''}'.trim();
    if (text.isEmpty) return null;
    final WaButtonType t = WaButtonTypeX.fromApi(j['type']);
    return WaButton(
      type: t,
      text: text,
      value: switch (t) {
        WaButtonType.url => j['url'] as String?,
        WaButtonType.phoneNumber =>
          (j['phone_number'] ?? j['phoneNumber']) as String?,
        WaButtonType.quickReply => null,
      },
    );
  }
}

class WhatsAppTemplate {
  const WhatsAppTemplate({
    required this.uid,
    required this.name,
    required this.language,
    required this.category,
    required this.body,
    this.status = WaTemplateStatus.unknown,
    this.headerText,
    this.footer,
    this.buttons = const <WaButton>[],
  });

  final String uid;

  /// Fixed once Meta holds the template — see [isNameLocked].
  final String name;
  final String language;
  final WaTemplateCategory category;
  final String body;
  final WaTemplateStatus status;
  final String? headerText;
  final String? footer;
  final List<WaButton> buttons;

  /// Name, language and category cannot change after creation: Meta keys the
  /// template on them. An editor that lets someone type into those fields and
  /// then silently ignores the change is worse than one that disables them.
  bool get isNameLocked => uid.isNotEmpty;

  static WhatsAppTemplate fromJson(Map<String, dynamic> j) {
    String? str(Object? v) {
      final String s = '${v ?? ''}'.trim();
      return s.isEmpty ? null : s;
    }

    // The content is Meta's own `components[]`, not flat columns.
    //
    // `whatsapp_templates` stores name, language, category and status as
    // columns and the rest inside `__data.template` — the raw object Meta
    // returns. So there is no `body` field to read, which is why an editor
    // built on one showed every content box empty on a template that plainly
    // had a body. Depth varies by endpoint, hence the three probes.
    final List<Map<String, dynamic>> components = <Map<String, dynamic>>[
      for (final Object? source in <Object?>[
        j['components'],
        (j['template'] as Map<String, dynamic>?)?['components'],
        ((j['__data'] as Map<String, dynamic>?)?['template']
            as Map<String, dynamic>?)?['components'],
      ])
        if (source is List)
          ...source.whereType<Map<String, dynamic>>(),
    ];

    Map<String, dynamic>? component(String type, {String? format}) {
      for (final Map<String, dynamic> c in components) {
        if ('${c['type'] ?? ''}'.toUpperCase() != type) continue;
        if (format != null &&
            '${c['format'] ?? ''}'.toUpperCase() != format) {
          continue;
        }
        return c;
      }
      return null;
    }

    // Flat keys win when present — a future shaper may well provide them — and
    // the components are the fallback that actually works today.
    final String body = str(j['body'] ?? j['text'] ?? j['template_body']) ??
        str(component('BODY')?['text']) ??
        '';
    final String? headerText = str(j['headerText'] ?? j['header_text_body']) ??
        str(component('HEADER', format: 'TEXT')?['text']);
    final String? footer = str(j['footer'] ?? j['template_footer']) ??
        str(component('FOOTER')?['text']);

    final List<dynamic> rawButtons =
        (j['buttons'] ?? j['message_buttons']) as List<dynamic>? ??
            (component('BUTTONS')?['buttons'] as List<dynamic>?) ??
            const <dynamic>[];

    return WhatsAppTemplate(
      uid: '${j['uid'] ?? j['_uid'] ?? ''}',
      name: '${j['name'] ?? j['template_name'] ?? ''}',
      language: '${j['language'] ?? j['language_code'] ?? ''}',
      category: WaTemplateCategoryX.fromApi(j['category']),
      body: body,
      status: WaTemplateStatusX.fromApi(j['status']),
      headerText: headerText,
      footer: footer,
      buttons: rawButtons
          .whereType<Map<String, dynamic>>()
          .map(WaButton.fromJson)
          .whereType<WaButton>()
          .toList(growable: false),
    );
  }

  /// The create/update body.
  ///
  /// snake_case, matching the console's own request shape — this endpoint wraps
  /// the console controller rather than defining its own contract.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'template_name': name,
        'language_code': language,
        'category': category.wire,
        'template_body': body,
        if (footer != null) 'template_footer': footer,
        if (headerText != null) ...<String, dynamic>{
          'media_header_type': 'text',
          'header_text_body': headerText,
        },
        if (buttons.isNotEmpty)
          'message_buttons': buttons.map((WaButton b) => b.toJson()).toList(),
      };
}
