import 'package:clickalize/features/inbox/domain/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Message-type parsing.
///
/// The type used to be implicit in the shape of a JSON blob, so every client
/// re-derived it. It is resolved server-side now, and the value that matters
/// most is the one nobody sends deliberately: an unrecognised type has to be
/// visible, because rendering it as empty text is how fifteen customer orders
/// became invisible.
void main() {
  test('parses the snake_case names the API sends', () {
    expect(MessageKindX.fromApi('text'), MessageKind.text);
    expect(MessageKindX.fromApi('interactive_buttons'),
        MessageKind.interactiveButtons);
    expect(MessageKindX.fromApi('interactive_list'), MessageKind.interactiveList);
    expect(MessageKindX.fromApi('location_request'), MessageKind.locationRequest);
    expect(MessageKindX.fromApi('product_list'), MessageKind.productList);
    expect(MessageKindX.fromApi('cta_url'), MessageKind.ctaUrl);
    expect(MessageKindX.fromApi('order'), MessageKind.order);
  });

  test('every documented type resolves to something other than unsupported', () {
    // The eighteen the resolver can emit. If the server adds one, this list is
    // where the gap shows up.
    const List<String> api = <String>[
      'text', 'image', 'video', 'audio', 'document', 'sticker',
      'location', 'location_request', 'contacts', 'template',
      'interactive_buttons', 'interactive_list', 'cta_url',
      'order', 'product', 'product_list', 'catalog', 'unsupported',
    ];
    for (final String t in api) {
      final MessageKind k = MessageKindX.fromApi(t);
      if (t == 'unsupported') {
        expect(k, MessageKind.unsupported);
      } else {
        expect(k, isNot(MessageKind.unsupported), reason: '$t must map');
      }
    }
  });

  test('an absent type is text, an unknown type is unsupported', () {
    // Two different situations that must not collapse into one. Absent means a
    // payload from before the typed rollout, which really was text. Unknown
    // means the server learned a type this build has not — showing that as
    // text would render a plausible-looking empty bubble.
    expect(MessageKindX.fromApi(null), MessageKind.text);
    expect(MessageKindX.fromApi('carrier_pigeon'), MessageKind.unsupported);
    expect(MessageKindX.fromApi(''), MessageKind.unsupported);
  });

  test('commerce kinds are grouped, because their bodies are always empty', () {
    for (final MessageKind k in <MessageKind>[
      MessageKind.order,
      MessageKind.product,
      MessageKind.productList,
      MessageKind.catalog,
    ]) {
      expect(k.isCommerce, isTrue, reason: '${k.name} carries no body text');
    }
    expect(MessageKind.text.isCommerce, isFalse);
    expect(MessageKind.image.isMedia, isTrue);
    expect(MessageKind.text.isMedia, isFalse);
  });
}
