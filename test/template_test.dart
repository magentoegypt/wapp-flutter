import 'package:clickalize/features/templates/domain/whatsapp_template.dart';
import 'package:flutter_test/flutter_test.dart';

/// WhatsApp template management.
///
/// The limits and field names here came from `WhatsAppTemplateController`'s
/// validation rules, not from the handoff — which documents none of them. Two
/// of these tests exist because the server validates per button type: sending a
/// phone number under `url` fails the `url` rule and surfaces as "invalid link"
/// rather than "wrong field".
void main() {
  group('the create body is the console\'s own shape', () {
    test('snake_case, with the header only when there is one', () {
      const WhatsAppTemplate t = WhatsAppTemplate(
        uid: '',
        name: 'order_update',
        language: 'en_US',
        category: WaTemplateCategory.utility,
        body: 'Your order shipped.',
      );

      final Map<String, dynamic> j = t.toJson();
      expect(j['template_name'], 'order_update');
      expect(j['language_code'], 'en_US');
      expect(j['category'], 'UTILITY');
      expect(j['template_body'], 'Your order shipped.');
      // The server branches on the key being present, so an unused header must
      // be absent rather than empty.
      expect(j.containsKey('media_header_type'), isFalse);
      expect(j.containsKey('header_text_body'), isFalse);
      expect(j.containsKey('template_footer'), isFalse);
      expect(j.containsKey('message_buttons'), isFalse);
    });

    test('a text header sends both of its keys', () {
      const WhatsAppTemplate t = WhatsAppTemplate(
        uid: '',
        name: 'n',
        language: 'en_US',
        category: WaTemplateCategory.marketing,
        body: 'b',
        headerText: 'Update',
        footer: 'Clickalize',
      );

      final Map<String, dynamic> j = t.toJson();
      expect(j['media_header_type'], 'text');
      expect(j['header_text_body'], 'Update');
      expect(j['template_footer'], 'Clickalize');
      expect(j['category'], 'MARKETING');
    });
  });

  group('buttons send only the field their type uses', () {
    test('a URL button sends url and not phone_number', () {
      const WaButton b = WaButton(
        type: WaButtonType.url,
        text: 'Track',
        value: 'https://example.com',
      );
      final Map<String, dynamic> j = b.toJson();
      expect(j['type'], 'URL_BUTTON');
      expect(j['url'], 'https://example.com');
      expect(j.containsKey('phone_number'), isFalse);
    });

    test('a phone button sends phone_number and not url', () {
      // The server validates `url` with Laravel's url rule. A phone number
      // under that key fails it, and the 422 reads as a malformed link rather
      // than as the wrong field being filled.
      const WaButton b = WaButton(
        type: WaButtonType.phoneNumber,
        text: 'Call us',
        value: '+201000000000',
      );
      final Map<String, dynamic> j = b.toJson();
      expect(j['type'], 'PHONE_NUMBER');
      expect(j['phone_number'], '+201000000000');
      expect(j.containsKey('url'), isFalse);
    });

    test('a quick reply sends neither', () {
      const WaButton b = WaButton(type: WaButtonType.quickReply, text: 'Yes');
      final Map<String, dynamic> j = b.toJson();
      expect(j['type'], 'QUICK_REPLY');
      expect(j.containsKey('url'), isFalse);
      expect(j.containsKey('phone_number'), isFalse);
    });

    test('a titleless button is dropped on the way in', () {
      expect(WaButton.fromJson(<String, dynamic>{'type': 'URL_BUTTON'}), isNull);
    });

    test('DYNAMIC_URL_BUTTON reads back as a URL button', () {
      // Meta has more button types than this editor offers. An unknown one
      // must land somewhere sensible rather than vanishing from the form and
      // then vanishing from the template on the next save.
      final WaButton? b = WaButton.fromJson(<String, dynamic>{
        'type': 'DYNAMIC_URL_BUTTON',
        'text': 'Track',
        'url': 'https://x.co',
      });
      expect(b!.type, WaButtonType.url);
    });
  });

  group('reading a template back', () {
    test('accepts either spelling of every field', () {
      // The list endpoint and the console's own form disagree on casing.
      final WhatsAppTemplate a = WhatsAppTemplate.fromJson(<String, dynamic>{
        'uid': 't1',
        'template_name': 'order_update',
        'language_code': 'en_US',
        'template_body': 'Body',
        'template_footer': 'Foot',
        'header_text_body': 'Head',
        'category': 'utility',
        'status': 'APPROVED',
      });

      expect(a.name, 'order_update');
      expect(a.language, 'en_US');
      expect(a.body, 'Body');
      expect(a.footer, 'Foot');
      expect(a.headerText, 'Head');
      expect(a.category, WaTemplateCategory.utility);
      expect(a.status, WaTemplateStatus.approved);
    });

    test('an empty header or footer reads as absent', () {
      final WhatsAppTemplate t = WhatsAppTemplate.fromJson(<String, dynamic>{
        'uid': 't2',
        'name': 'n',
        'header_text_body': '',
        'template_footer': '   ',
      });
      expect(t.headerText, isNull);
      expect(t.footer, isNull);
    });

    test('only an approved template is sendable', () {
      expect(WaTemplateStatus.approved.isSendable, isTrue);
      expect(WaTemplateStatus.pending.isSendable, isFalse);
      expect(WaTemplateStatus.rejected.isSendable, isFalse);
    });

    test('an unrecognised status is unknown, not approved', () {
      // Defaulting to approved would show a send affordance for a template
      // Meta has not cleared.
      expect(WaTemplateStatusX.fromApi('something_new'),
          WaTemplateStatus.unknown);
      expect(WaTemplateStatusX.fromApi(null), WaTemplateStatus.unknown);
    });

    test('a saved template reports its identity as locked', () {
      const WhatsAppTemplate saved = WhatsAppTemplate(
        uid: 't1',
        name: 'n',
        language: 'en_US',
        category: WaTemplateCategory.utility,
        body: 'b',
      );
      const WhatsAppTemplate fresh = WhatsAppTemplate(
        uid: '',
        name: 'n',
        language: 'en_US',
        category: WaTemplateCategory.utility,
        body: 'b',
      );
      expect(saved.isNameLocked, isTrue);
      expect(fresh.isNameLocked, isFalse);
    });
  });

  group('content comes from Meta components, not flat fields', () {
    // `whatsapp_templates` keeps name, language, category and status as columns
    // and everything else inside `__data.template` — Meta's raw object. There
    // is no `body` column, so an editor reading one shows an empty form on a
    // template that plainly has a body, with nothing anywhere reporting a
    // problem.
    Map<String, dynamic> meta(List<Map<String, dynamic>> components) =>
        <String, dynamic>{
          'uid': 't1',
          'template_name': 'order_update',
          'language': 'en_US',
          'category': 'UTILITY',
          'status': 'APPROVED',
          'components': components,
        };

    test('BODY, HEADER:TEXT, FOOTER and BUTTONS are all read', () {
      final WhatsAppTemplate t = WhatsAppTemplate.fromJson(meta(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'HEADER',
            'format': 'TEXT',
            'text': 'Update',
          },
          <String, dynamic>{'type': 'BODY', 'text': 'Your order shipped.'},
          <String, dynamic>{'type': 'FOOTER', 'text': 'Clickalize'},
          <String, dynamic>{
            'type': 'BUTTONS',
            'buttons': <dynamic>[
              <String, dynamic>{
                'type': 'URL',
                'text': 'Track',
                'url': 'https://x.co',
              },
            ],
          },
        ],
      ));

      expect(t.body, 'Your order shipped.');
      expect(t.headerText, 'Update');
      expect(t.footer, 'Clickalize');
      expect(t.buttons.single.text, 'Track');
      expect(t.buttons.single.type, WaButtonType.url);
    });

    test('an IMAGE header is not mistaken for a text one', () {
      // A media header has no `text`. Reading the first HEADER regardless of
      // format would set headerText to null and still switch the form to the
      // text variant.
      final WhatsAppTemplate t = WhatsAppTemplate.fromJson(meta(
        <Map<String, dynamic>>[
          <String, dynamic>{'type': 'HEADER', 'format': 'IMAGE'},
          <String, dynamic>{'type': 'BODY', 'text': 'b'},
        ],
      ));
      expect(t.headerText, isNull);
      expect(t.body, 'b');
    });

    test('components nested under `template` are found', () {
      final WhatsAppTemplate t = WhatsAppTemplate.fromJson(<String, dynamic>{
        'uid': 't2',
        'template': <String, dynamic>{
          'components': <dynamic>[
            <String, dynamic>{'type': 'BODY', 'text': 'Nested'},
          ],
        },
      });
      expect(t.body, 'Nested');
    });

    test('components nested under `__data.template` are found', () {
      final WhatsAppTemplate t = WhatsAppTemplate.fromJson(<String, dynamic>{
        'uid': 't3',
        '__data': <String, dynamic>{
          'template': <String, dynamic>{
            'components': <dynamic>[
              <String, dynamic>{'type': 'BODY', 'text': 'Deep'},
            ],
          },
        },
      });
      expect(t.body, 'Deep');
    });

    test('a flat body wins over components when both are present', () {
      final WhatsAppTemplate t = WhatsAppTemplate.fromJson(<String, dynamic>{
        'uid': 't4',
        'body': 'Flat',
        'components': <dynamic>[
          <String, dynamic>{'type': 'BODY', 'text': 'FromComponents'},
        ],
      });
      expect(t.body, 'Flat');
    });
  });

  group('limits match the server validation', () {
    test('caps are the ones the API enforces', () {
      expect(WaTemplateLimits.name, 512);
      expect(WaTemplateLimits.language, 15);
      expect(WaTemplateLimits.body, 1024);
      expect(WaTemplateLimits.footer, 60);
      expect(WaTemplateLimits.headerText, 60);
      expect(WaTemplateLimits.buttonText, 25);
      expect(WaTemplateLimits.buttonUrl, 2000);
    });
  });
}
