import 'package:clickalize/core/error/failure.dart';
import 'package:clickalize/features/contacts/data/contact_repository.dart';
import 'package:clickalize/features/contacts/domain/contact.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contact groups and the two 403s.
///
/// Both of these were silent: the group uid was dropped at the mapper, so the
/// remove endpoint could not be called at all and nothing said so; and a plan
/// refusal was reported with a permission refusal's wording, which sends an
/// owner to ask an admin for access they already have.
void main() {
  group('groups keep their uid', () {
    test('a group parses to a NamedRef, not a bare name', () {
      // `strings()` used to flatten these to names. The remove endpoint needs
      // the uid, so the flattening did not merely lose detail — it made the
      // call impossible to construct.
      final Contact c = contactFromJson(<String, dynamic>{
        'uid': 'c1',
        'name': 'Amira',
        'phone': '+201000000000',
        'groups': <dynamic>[
          <String, dynamic>{'uid': 'g-vip', 'name': 'VIP'},
          <String, dynamic>{'uid': 'g-cairo', 'name': 'Cairo'},
        ],
      });

      expect(c.groups.length, 2);
      expect(c.groups.first.id, 'g-vip');
      expect(c.groups.first.name, 'VIP');
    });

    test('a nameless group is dropped rather than rendered blank', () {
      final Contact c = contactFromJson(<String, dynamic>{
        'uid': 'c1',
        'groups': <dynamic>[
          <String, dynamic>{'uid': 'g1'},
          <String, dynamic>{'uid': 'g2', 'name': 'Cairo'},
        ],
      });
      expect(c.groups.length, 1);
      expect(c.groups.single.name, 'Cairo');
    });

    test('a group with no uid still shows, and is inert', () {
      // The chip renders without a remove control in this case rather than
      // offering one that would 404.
      final Contact c = contactFromJson(<String, dynamic>{
        'uid': 'c1',
        'groups': <dynamic>[
          <String, dynamic>{'name': 'Legacy'},
        ],
      });
      expect(c.groups.single.name, 'Legacy');
      expect(c.groups.single.id, isEmpty);
    });
  });

  group('Instagram contacts do not show an IGSID as a phone number', () {
    test('an Instagram contact falls back to no subtitle, never the IGSID', () {
      final Contact c = contactFromJson(<String, dynamic>{
        'uid': 'c2',
        'name': 'Mera Ahmed',
        // waId holds the IGSID for an Instagram contact — 16 digits that read
        // as a malformed phone number beside real ones.
        'waId': '1029835992858852',
        'channel': 'instagram',
      });

      expect(c.phone, '1029835992858852', reason: 'still parsed');
      expect(c.subtitleLine, isNull, reason: 'but never displayed as a number');
    });

    test('an Instagram contact with a username shows it with an @', () {
      final Contact c = contactFromJson(<String, dynamic>{
        'uid': 'c3',
        'name': 'Mera',
        'waId': '1029835992858852',
        'channel': 'instagram',
        'instagramUsername': 'mera.ahmed',
      });
      expect(c.subtitleLine, '@mera.ahmed');
    });

    test('an already-@ username is not double-prefixed', () {
      final Contact c = contactFromJson(<String, dynamic>{
        'uid': 'c4',
        'channel': 'instagram',
        'instagramUsername': '@mera.ahmed',
      });
      expect(c.subtitleLine, '@mera.ahmed');
    });

    test('a WhatsApp contact still shows its number', () {
      final Contact c = contactFromJson(<String, dynamic>{
        'uid': 'c5',
        'name': 'Mahmoud',
        'phone': '201020104267',
      });
      expect(c.subtitleLine, '201020104267');
    });
  });

  group('a plan limit is not a permission refusal', () {
    // Both arrive as 403. Only the plan one carries `module`, and only the
    // plan one is something the workspace owner can act on.
    test('PlanLimitFailure keeps the module the server named', () {
      const PlanLimitFailure f = PlanLimitFailure(
        'This module is not included in your current subscription plan.',
        'contacts_module',
      );
      expect(f.module, 'contacts_module');
      expect(f, isA<Failure>());
      expect(f, isNot(isA<ForbiddenFailure>()));
    });

    test('the two are distinguishable by type, not by message text', () {
      const ForbiddenFailure perm = ForbiddenFailure();
      const PlanLimitFailure plan = PlanLimitFailure('nope', 'inbox_module');
      expect(perm, isNot(isA<PlanLimitFailure>()));
      expect(plan.module, isNotNull);
    });
  });
}
