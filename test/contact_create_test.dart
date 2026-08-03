import 'package:clickalize/features/contacts/data/contact_repository.dart';
import 'package:clickalize/features/contacts/domain/contact.dart';
import 'package:flutter_test/flutter_test.dart';

/// The wire contract for `POST /contacts`, and the country list behind it.
///
/// Add contact could not create anyone. It sent `name`, `phone` and `groups`;
/// the endpoint validates `first_name` (required), `last_name`, `phone_number`
/// (required), `email`, `country`, `language_code`, `contact_city`,
/// `contact_tags` and `contact_groups`. Two required fields were therefore
/// always absent, so every submission failed validation before reaching the
/// engine — and the 422 came back naming fields the form did not display, which
/// is why it read as a mysterious server error rather than a client bug.
///
/// `update()` had the keys right the whole time. Only `create()` was left on
/// the older shape, which is exactly the kind of drift a test pins cheaply and
/// review misses.
///
/// These assert the JSON body rather than the mapper, because the body is the
/// part that was wrong and the part nothing else checks.
void main() {
  group('create payload', () {
    test('sends the snake_case keys the endpoint validates', () {
      final Map<String, dynamic> body = buildCreateBody(
        firstName: 'Amira',
        lastName: 'Khalifa',
        phoneNumber: '201002345678',
        email: 'amira@example.com',
        countryId: '64',
        city: 'Cairo',
        tags: 'vip,wholesale',
        groupIds: <String>['g1', 'g2'],
      );

      expect(body['first_name'], 'Amira');
      expect(body['last_name'], 'Khalifa');
      expect(body['phone_number'], '201002345678');
      expect(body['email'], 'amira@example.com');
      expect(body['country'], '64');
      expect(body['contact_city'], 'Cairo');
      expect(body['contact_tags'], 'vip,wholesale');
      expect(body['contact_groups'], <String>['g1', 'g2']);

      // The three keys that used to be sent and are read by nothing.
      expect(body.containsKey('name'), isFalse);
      expect(body.containsKey('phone'), isFalse);
      expect(body.containsKey('groups'), isFalse);
    });

    test('omits blank optionals rather than sending empty strings', () {
      // `email` is `nullable|email`. An empty string is not "no email" to that
      // rule — it is an invalid one, so sending "" would 422 a form whose
      // optional fields the user simply left alone.
      final Map<String, dynamic> body = buildCreateBody(
        firstName: 'Amira',
        lastName: '',
        phoneNumber: '201002345678',
        email: '',
        countryId: '',
        city: '',
        tags: '',
        groupIds: const <String>[],
      );

      expect(body.keys.toSet(), <String>{'first_name', 'phone_number'});
    });

    test('a first name and a phone number are always present', () {
      // Both are `required` server-side, so they are sent unconditionally —
      // never behind an `if (isNotEmpty)` that could drop them.
      final Map<String, dynamic> body = buildCreateBody(
        firstName: 'Amira',
        phoneNumber: '201002345678',
      );
      expect(body.containsKey('first_name'), isTrue);
      expect(body.containsKey('phone_number'), isTrue);
    });
  });

  group('countries', () {
    test('reads the numeric id, not a uid', () {
      // The countries list is the one entry in /contacts/meta with no `uid`.
      // Running it through the shared `_refs` helper, which prefers `uid`,
      // yielded empty ids — a populated dropdown that submitted nothing.
      final ContactMeta meta = contactMetaFromJson(<String, dynamic>{
        'countries': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 64,
            'name': 'Egypt',
            'isoCode': 'EG',
            'phoneCode': '20',
          },
        ],
      });

      expect(meta.countries, hasLength(1));
      expect(meta.countries.first.id, '64');
      expect(meta.countries.first.name, 'Egypt');
      expect(meta.countries.first.phoneCode, '20');
    });

    test('groups keep both identifiers, because both are needed', () {
      // `contact_groups` on create/update is resolved with whereIn('_id', …),
      // while the remove endpoint and the campaign audience take the uid.
      // Routing groups through the shared ref helper — which prefers uid —
      // assigned no groups on create; on update the engine computes removals as
      // array_diff(existingIds, sent), so a list of uids matched nothing and
      // dropped every group the contact had.
      final ContactMeta meta = contactMetaFromJson(<String, dynamic>{
        'groups': <Map<String, dynamic>>[
          <String, dynamic>{'uid': 'g-uid-1', 'id': 7, 'title': 'test group'},
        ],
      });

      expect(meta.groups, hasLength(1));
      expect(meta.groups.first.id, '7');
      expect(meta.groups.first.uid, 'g-uid-1');
      expect(meta.groups.first.name, 'test group');
    });

    test('create sends numeric group ids', () {
      final Map<String, dynamic> body = buildCreateBody(
        firstName: 'Amira',
        phoneNumber: '201002345678',
        groupIds: <String>['7'],
      );
      expect(body['contact_groups'], <String>['7']);
    });

    test('custom field values are keyed by field uid', () {
      // custom_input_fields[<uid>] = value — the create path does consume
      // these, so a workspace with required custom fields can be filled in
      // from the app instead of being completed later in the console.
      final Map<String, dynamic> body = buildCreateBody(
        firstName: 'Amira',
        phoneNumber: '201002345678',
        customFields: <String, String>{'f-uid': 'Female'},
      );
      expect(body['custom_input_fields'], <String, String>{'f-uid': 'Female'});
    });

    test('no custom fields means the key is absent', () {
      final Map<String, dynamic> body = buildCreateBody(
        firstName: 'Amira',
        phoneNumber: '201002345678',
      );
      expect(body.containsKey('custom_input_fields'), isFalse);
    });

    test('a row with no id is dropped, not shown with an unusable value', () {
      final ContactMeta meta = contactMetaFromJson(<String, dynamic>{
        'countries': <Map<String, dynamic>>[
          <String, dynamic>{'name': 'Nowhere'},
          <String, dynamic>{'id': 1, 'name': 'Egypt'},
        ],
      });
      expect(meta.countries, hasLength(1));
      expect(meta.countries.first.name, 'Egypt');
    });
  });
}
