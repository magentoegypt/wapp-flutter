import 'package:clickalize/features/inbox/data/conversation_repository.dart';
import 'package:clickalize/features/inbox/domain/conversation.dart';
import 'package:clickalize/features/inbox/domain/message_payload.dart';
import 'package:flutter_test/flutter_test.dart';

/// The structured half of a message.
///
/// Every failure mode here is a blank or wrong bubble rather than an
/// exception, which is exactly how fifteen real customer carts — one of them
/// SAR 31,500 — sat invisible in this app: the type was known, the payload was
/// dropped at the mapper, and nothing anywhere threw.
void main() {
  group('empty strings are absent, not present', () {
    // The API returns "" rather than null for headerText, footerText and
    // mediaLink on many rows. Treated as present they render as blank header
    // space, which reads as a broken bubble rather than a missing field.
    test('blank media link and file name read as null', () {
      final MessageMedia? m = MessageMedia.fromJson(<String, dynamic>{
        'mediaLink': '',
        'fileName': '   ',
        'caption': 'Look at this',
      });

      expect(m, isNotNull);
      expect(m!.link, isNull);
      expect(m.fileName, isNull);
      expect(m.caption, 'Look at this');
    });

    test('blank header and footer read as null', () {
      final MessageInteractive? i = MessageInteractive.fromJson(
        <String, dynamic>{'headerText': '', 'footerText': ''},
      );
      expect(i!.headerText, isNull);
      expect(i.footerText, isNull);
    });
  });

  group('order carts', () {
    Map<String, dynamic> cart(Object? total) => <String, dynamic>{
          'itemCount': 2,
          'currency': 'SAR',
          'total': total,
          'items': <dynamic>[
            <String, dynamic>{
              'name': 'Abaya',
              'quantity': 1,
              'unitPrice': 31000,
              'lineTotal': 31000,
              'currency': 'SAR',
            },
            <String, dynamic>{
              'name': 'Scarf',
              'quantity': 2,
              'unitPrice': 250,
              'lineTotal': 500,
              'currency': 'SAR',
            },
          ],
        };

    test('lines and total parse', () {
      final MessageOrder? o = MessageOrder.fromJson(cart(31500));
      expect(o!.items.length, 2);
      expect(o.items.first.name, 'Abaya');
      expect(o.items.first.lineTotal, 31000);
      expect(o.total, 31500);
      expect(o.count, 2);
    });

    // The server withholds `total` when the cart mixes currencies. Summing the
    // lines ourselves would add SAR to USD and print a confident wrong number,
    // so a null total has to stay null all the way to the bubble.
    test('a withheld total is not reconstructed', () {
      final MessageOrder? o = MessageOrder.fromJson(cart(null));
      expect(o!.total, isNull);
      expect(o.isMixedCurrency, isTrue);
      expect(o.items.length, 2, reason: 'lines must still render');
    });

    test('count falls back to the lines when itemCount is missing', () {
      final MessageOrder? o = MessageOrder.fromJson(<String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'name': 'One'},
        ],
      });
      expect(o!.count, 1);
    });

    test('an item with no name falls back to its retailer id', () {
      // Catalog items can arrive nameless; the retailer id is the only other
      // handle an agent has on which product it is. Empty would be a blank row.
      final MessageOrder? o = MessageOrder.fromJson(<String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'retailerId': 'SKU-99', 'quantity': 1},
        ],
      });
      expect(o!.items.single.name, 'SKU-99');
    });
  });

  group('interactive', () {
    test('buttons parse as a list of {id,title}', () {
      final MessageInteractive? i = MessageInteractive.fromJson(<String, dynamic>{
        'buttons': <dynamic>[
          <String, dynamic>{'id': 'b1', 'title': 'Track order'},
          <String, dynamic>{'id': 'b2', 'title': 'Talk to an agent'},
        ],
      });
      expect(i!.buttons.map((InteractiveButton b) => b.title),
          <String>['Track order', 'Talk to an agent']);
    });

    test('a titleless button is dropped rather than rendered blank', () {
      final MessageInteractive? i = MessageInteractive.fromJson(<String, dynamic>{
        'buttons': <dynamic>[
          <String, dynamic>{'id': 'b1'},
          <String, dynamic>{'id': 'b2', 'title': 'Yes'},
        ],
      });
      expect(i!.buttons.length, 1);
      expect(i.buttons.single.title, 'Yes');
    });

    test('list sections count their rows across sections', () {
      final MessageInteractive? i = MessageInteractive.fromJson(<String, dynamic>{
        'listButtonText': 'Choose',
        'listSections': <dynamic>[
          <String, dynamic>{
            'title': 'Tops',
            'rows': <dynamic>[
              <String, dynamic>{'title': 'Shirt'},
              <String, dynamic>{'title': 'Blouse'},
            ],
          },
          <String, dynamic>{
            'title': 'Shoes',
            'rows': <dynamic>[
              <String, dynamic>{'title': 'Sandals'},
            ],
          },
        ],
      });
      expect(i!.listSections.length, 2);
      expect(i.listRowCount, 3);
      expect(i.listButtonText, 'Choose');
    });

    test('a contact name is read from either shape', () {
      // Meta nests it under name.formatted_name; the API has been seen to
      // flatten it. Reading only one shape yields a nameless card.
      final MessageInteractive? nested =
          MessageInteractive.fromJson(<String, dynamic>{
        'contacts': <dynamic>[
          <String, dynamic>{
            'name': <String, dynamic>{'formatted_name': 'Amira Hassan'},
            'phones': <dynamic>[
              <String, dynamic>{'phone': '+201000000000'},
            ],
          },
        ],
      });
      expect(nested!.contacts.single.name, 'Amira Hassan');
      expect(nested.contacts.single.phones.single, '+201000000000');

      final MessageInteractive? flat = MessageInteractive.fromJson(
        <String, dynamic>{
          'contacts': <dynamic>[
            <String, dynamic>{'name': 'Amira Hassan'},
          ],
        },
      );
      expect(flat!.contacts.single.name, 'Amira Hassan');
    });

    test('a catalog with no id still parses', () {
      // 18 of 29 live catalog messages have no catalog id. Requiring it would
      // drop the payload and leave the bubble empty.
      final MessageInteractive? i = MessageInteractive.fromJson(
        <String, dynamic>{'catalog': <String, dynamic>{}},
      );
      expect(i!.catalog, isNotNull);
      expect(i.catalog!.catalogId, isNull);
    });
  });

  group('templates', () {
    test('components are addressable by role', () {
      final MessageTemplate? t = MessageTemplate.fromJson(<String, dynamic>{
        'name': 'order_update',
        'category': 'utility',
        'components': <dynamic>[
          <String, dynamic>{'type': 'HEADER', 'format': 'TEXT', 'text': 'Update'},
          <String, dynamic>{'type': 'BODY', 'text': 'Your order shipped.'},
          <String, dynamic>{'type': 'FOOTER', 'text': 'Clickalize'},
          <String, dynamic>{
            'type': 'BUTTONS',
            'buttons': <dynamic>[
              <String, dynamic>{'type': 'URL', 'text': 'Track', 'url': 'https://x.co'},
              <String, dynamic>{'type': 'PHONE_NUMBER', 'text': 'Call us'},
            ],
          },
        ],
      });

      expect(t!.category, 'UTILITY', reason: 'category is normalised upper');
      expect(t.header?.text, 'Update');
      expect(t.body?.text, 'Your order shipped.');
      expect(t.footer?.text, 'Clickalize');
      expect(t.buttons.length, 2);
      expect(t.buttons.first.value, 'https://x.co');
    });

    test('an image header carries no text and does not crash', () {
      final MessageTemplate? t = MessageTemplate.fromJson(<String, dynamic>{
        'components': <dynamic>[
          <String, dynamic>{'type': 'HEADER', 'format': 'IMAGE'},
        ],
      });
      expect(t!.header?.format, 'IMAGE');
      expect(t.header?.text, isNull);
    });
  });

  group('the mapper attaches payloads', () {
    // The real defect: kind was parsed and every payload was dropped, so the
    // bubble knew it was an order and had nothing to show.
    test('an order message carries its cart through chatMessageFromJson', () {
      final ChatMessage m = chatMessageFromJson(<String, dynamic>{
        'uid': 'm1',
        'type': 'order',
        'body': '',
        'isIncoming': true,
        'order': <String, dynamic>{
          'itemCount': 1,
          'currency': 'SAR',
          'total': 31500,
          'items': <dynamic>[
            <String, dynamic>{'name': 'Abaya', 'quantity': 1, 'lineTotal': 31500},
          ],
        },
      });

      expect(m.kind, MessageKind.order);
      expect(m.order, isNotNull);
      expect(m.order!.items.single.name, 'Abaya');
      expect(m.order!.total, 31500);
    });

    test('a plain text message has all four payloads null', () {
      final ChatMessage m = chatMessageFromJson(<String, dynamic>{
        'uid': 'm2',
        'type': 'text',
        'body': 'hello',
        'isIncoming': true,
        'media': null,
        'interactive': null,
        'template': null,
        'order': null,
      });

      expect(m.media, isNull);
      expect(m.interactive, isNull);
      expect(m.template, isNull);
      expect(m.order, isNull);
    });

    test('bot and campaign attribution survive the mapper', () {
      final ChatMessage bot = chatMessageFromJson(<String, dynamic>{
        'uid': 'm3',
        'body': 'auto',
        'isIncoming': false,
        'isBotReply': true,
      });
      expect(bot.isBotReply, isTrue);

      // `campaign` has been seen both as an object and as a bare name.
      final ChatMessage obj = chatMessageFromJson(<String, dynamic>{
        'uid': 'm4',
        'body': 'blast',
        'isIncoming': false,
        'campaign': <String, dynamic>{'name': 'Eid sale'},
      });
      expect(obj.campaignName, 'Eid sale');
    });
  });
}
