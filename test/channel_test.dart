import 'package:clickalize/features/inbox/data/instagram_repository.dart';
import 'package:clickalize/features/inbox/domain/channel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Channel parsing and the Instagram send limits.
///
/// The limits are the part worth testing. Meta **trims** over-long titles
/// rather than rejecting them, so a button reading "Track my order now" comes
/// back shorter with no error and no indication anything happened. The server
/// will not catch it either — this is the one validation that only exists on
/// the client, so it is the one most worth a regression test.
void main() {
  group('MessageChannelX.fromApi', () {
    test('reads the two wire values', () {
      expect(MessageChannelX.fromApi('instagram'), MessageChannel.instagram);
      expect(MessageChannelX.fromApi('whatsapp'), MessageChannel.whatsapp);
      expect(MessageChannelX.fromApi('Instagram'), MessageChannel.instagram);
      expect(MessageChannelX.fromApi('  instagram  '), MessageChannel.instagram);
    });

    test('anything unknown is whatsapp, not a third state', () {
      // The field is defaulted server-side and never null, so there is no
      // "unknown" a screen would know how to draw. Falling back to the
      // overwhelmingly common channel beats inventing one.
      expect(MessageChannelX.fromApi(null), MessageChannel.whatsapp);
      expect(MessageChannelX.fromApi(''), MessageChannel.whatsapp);
      expect(MessageChannelX.fromApi('telegram'), MessageChannel.whatsapp);
      expect(MessageChannelX.fromApi(7), MessageChannel.whatsapp);
    });

    test('the badge uses the network brand colours, not the app palette', () {
      // A green Instagram badge would be actively misleading — the badge means
      // "this is that network".
      expect(MessageChannel.instagram.badgeColor.toARGB32(), 0xFFE0356C);
      expect(MessageChannel.whatsapp.badgeColor.toARGB32(), 0xFF25D366);
      expect(MessageChannel.instagram.isInstagram, isTrue);
      expect(MessageChannel.whatsapp.isInstagram, isFalse);
    });
  });

  group('IgLimits — the caps Meta enforces silently', () {
    test('match the documented values', () {
      expect(IgLimits.title, 20);
      expect(IgLimits.cardText, 80);
      expect(IgLimits.maxQuickReplies, 13);
      expect(IgLimits.maxButtons, 3);
      expect(IgLimits.maxCards, 10);
    });

    test('a title at the cap is fine and one over it is not', () {
      const String ok = '12345678901234567890'; // exactly 20
      const String over = 'Track my order now please'; // 25
      expect(ok.length <= IgLimits.title, isTrue);
      expect(over.length <= IgLimits.title, isFalse,
          reason: 'this is the string Meta would trim without telling anyone');
    });
  });

  group('Instagram payload shaping', () {
    test('optional fields are omitted rather than sent empty', () {
      // An empty payload key is not the same as no key, and Meta treats the
      // two differently.
      expect(const IgQuickReply(title: 'Yes').toJson(),
          <String, dynamic>{'title': 'Yes'});
      expect(
        const IgQuickReply(title: 'Yes', payload: 'YES').toJson(),
        <String, dynamic>{'title': 'Yes', 'payload': 'YES'},
      );
      expect(const IgQuickReply(title: 'Yes', payload: '').toJson(),
          <String, dynamic>{'title': 'Yes'});
    });

    test('a button carries either a payload or a url, never empty strings', () {
      expect(
        const IgButton(type: 'web_url', title: 'Track', url: 'https://x.test')
            .toJson(),
        <String, dynamic>{
          'type': 'web_url',
          'title': 'Track',
          'url': 'https://x.test',
        },
      );
      expect(
        const IgButton(type: 'postback', title: 'Yes', payload: 'Y').toJson(),
        <String, dynamic>{'type': 'postback', 'title': 'Yes', 'payload': 'Y'},
      );
    });

    test('a card omits its optional parts and its empty button list', () {
      expect(const IgCard(title: 'Shoe').toJson(),
          <String, dynamic>{'title': 'Shoe'});
      final Map<String, dynamic> full = const IgCard(
        title: 'Shoe',
        subtitle: 'Blue',
        imageUrl: 'https://x.test/a.png',
        buttons: <IgButton>[IgButton(type: 'postback', title: 'Buy')],
      ).toJson();
      expect(full['subtitle'], 'Blue');
      expect((full['buttons'] as List<dynamic>).length, 1);
    });
  });

  group('IgTemplateKind wire values', () {
    test('differ from the endpoint names, which is easy to get wrong', () {
      expect(IgTemplateKind.quickReply.wire, 'quick_reply');
      expect(IgTemplateKind.button.wire, 'button');
      expect(IgTemplateKind.generic.wire, 'generic');
    });
  });
}
