import 'package:clickalize/features/settings/data/messenger_profile_repository.dart';
import 'package:clickalize/features/settings/domain/messenger_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Instagram's Messenger profile — the two things here that fail silently.
///
/// Both save endpoints replace the whole profile rather than merging into it,
/// and Meta trims over-long values instead of refusing them. So the failure
/// mode for this screen is never an exception: it is a menu that comes back
/// shorter than it was sent, or a language that quietly stops existing.

LocaleBlock<MenuAction> _menu(String locale, List<String> titles) =>
    LocaleBlock<MenuAction>(
      locale: locale,
      actions: titles
          .map((String t) =>
              MenuAction(type: 'postback', title: t, payload: 'P_$t'))
          .toList(),
    );

void main() {
  group('replaceLocale keeps the locales the screen cannot edit', () {
    // The screen edits `default` only. The save endpoint replaces the entire
    // profile, so sending just that block would delete every other language the
    // workspace configured on the web console — with a 200 and no warning.
    test('other locales survive an edit to default', () {
      final List<LocaleBlock<MenuAction>> existing = <LocaleBlock<MenuAction>>[
        _menu('default', <String>['Help']),
        _menu('ar_AR', <String>['المساعدة']),
        _menu('fr_FR', <String>['Aide']),
      ];

      final List<LocaleBlock<MenuAction>> out = replaceLocale<MenuAction>(
        existing,
        'default',
        <MenuAction>[
          const MenuAction(type: 'postback', title: 'Orders', payload: 'P_O'),
        ],
      );

      expect(out.length, 3, reason: 'a locale was dropped by the save');
      expect(out.map((LocaleBlock<MenuAction> b) => b.locale),
          <String>['default', 'ar_AR', 'fr_FR']);
      expect(out.first.actions.single.title, 'Orders');
      // Untouched blocks must go back byte-for-byte, not rebuilt from the form.
      expect(out[1].actions.single.title, 'المساعدة');
      expect(out[2].actions.single.title, 'Aide');
    });

    test('adds the default block when the profile had none', () {
      final List<LocaleBlock<MenuAction>> out = replaceLocale<MenuAction>(
        <LocaleBlock<MenuAction>>[_menu('ar_AR', <String>['المساعدة'])],
        'default',
        <MenuAction>[
          const MenuAction(type: 'postback', title: 'Help', payload: 'P_H'),
        ],
      );

      expect(out.length, 2);
      expect(out.last.locale, 'default');
    });

    test('an emptied default block is dropped, not sent empty', () {
      // The server requires call_to_actions to have at least one row, so an
      // empty block fails the whole request — taking the other locales with it.
      final List<LocaleBlock<MenuAction>> out = replaceLocale<MenuAction>(
        <LocaleBlock<MenuAction>>[
          _menu('default', <String>['Help']),
          _menu('ar_AR', <String>['المساعدة']),
        ],
        'default',
        <MenuAction>[],
      );

      expect(out.length, 1);
      expect(out.single.locale, 'ar_AR');
    });
  });

  group('wire shapes', () {
    test('a menu action emits only the key its type uses', () {
      // Emitting both is not a validation error, which is the problem: Meta
      // keeps whichever it prefers and the live menu stops matching the form.
      const MenuAction postback =
          MenuAction(type: 'postback', title: 'Orders', payload: 'P_ORDERS');
      expect(postback.toJson(), <String, dynamic>{
        'type': 'postback',
        'title': 'Orders',
        'payload': 'P_ORDERS',
      });
      expect(postback.toJson().containsKey('url'), isFalse);

      const MenuAction web = MenuAction(
        type: 'web_url',
        title: 'Shop',
        url: 'https://example.com',
      );
      expect(web.toJson().containsKey('payload'), isFalse);
      expect(web.toJson()['url'], 'https://example.com');
    });

    test('a missing locale reads back as the default, not as empty', () {
      // Meta omits `locale` entirely on a single-locale profile. Reading that
      // as '' would make it a foreign block, and the screen would then treat
      // the workspace's only menu as somebody else's and never show it.
      final LocaleBlock<MenuAction> b = LocaleBlock.fromJson<MenuAction>(
        <String, dynamic>{
          'call_to_actions': <dynamic>[
            <String, dynamic>{'type': 'postback', 'title': 'Help'},
          ],
        },
        MenuAction.fromJson,
      );

      expect(b.locale, kDefaultLocale);
      expect(b.isDefault, isTrue);
      expect(b.actions.single.title, 'Help');
    });
  });

  group('limits match the server validation', () {
    // Taken from the controller's rules, not the handoff prose, which omits
    // the ice-breaker question cap entirely.
    test('caps are the ones the API enforces', () {
      expect(IgProfileLimits.maxMenuActions, 5);
      expect(IgProfileLimits.menuTitle, 30);
      expect(IgProfileLimits.maxIceBreakers, 4);
      expect(IgProfileLimits.iceQuestion, 80);
    });
  });
}
