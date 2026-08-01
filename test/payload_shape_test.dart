import 'package:clickalize/features/contacts/data/contact_repository.dart';
import 'package:clickalize/features/contacts/domain/contact.dart';
import 'package:clickalize/features/dashboard/data/dashboard_repository.dart';
import 'package:clickalize/features/inbox/data/note_repository.dart';
import 'package:clickalize/features/inbox/domain/internal_note.dart';
import 'package:clickalize/features/dashboard/domain/dashboard_summary.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fields the app read by a name the API does not use.
///
/// Every one of these failed the same way: the mapper looked for a key that is
/// never sent, got null, and the screen rendered the "no data" branch. Nothing
/// threw, nothing logged, and no amount of real data would have changed the
/// result — the Contacts stage pill was blank on all thirty contacts, and the
/// weekly chart reported a silent week over a week with traffic.
///
/// The payloads below are copied verbatim off the wire. That is the point: a
/// hand-written fixture would have been written from the same wrong assumption
/// as the mapper.
void main() {
  group('a contact carries customerType, not status', () {
    // One row of GET /contacts, unedited.
    final Map<String, dynamic> row = <String, dynamic>{
      'uid': '7f0b4cd6-9c32-42f0-ad7a-27ad72ffdb9b',
      'firstName': 'Mahmoud',
      'lastName': 'Magdy',
      'name': 'Mahmoud Magdy',
      'waId': '201020104267',
      'phone': '201020104267',
      'email': 'mahmoudmagdy74237@gmail.com',
      'channel': 'whatsapp',
      'country': 'Egypt',
      'languageCode': 'en',
      'customerType': 'new',
      'favorite': false,
      'assignedUserUid': null,
      'createdAt': '2026-07-09T12:14:09+00:00',
      'labels': <dynamic>[],
    };

    test('the stage is read and is not null', () {
      // There is no `status` key anywhere in this payload. Reading one is what
      // made the pill absent on every row in the workspace.
      expect(row.containsKey('status'), isFalse);

      final Contact c = contactFromJson(row);
      expect(c.lifecycleStage, LifecycleStage.newCustomer);
      expect(c.isBlocked, isFalse);
      expect(c.isFavorite, isFalse);
    });

    test('the vocabulary is the backend\'s, not the frame\'s', () {
      // The frame segments by Customer / Lead / VIP. The workspace only ever
      // sends these two, so those three would be pills nothing can produce.
      expect(LifecycleStage.values.map((LifecycleStage s) => s.wire),
          <String>['new', 'returning']);
      expect(LifecycleStage.fromApi('returning'), LifecycleStage.returning);
      expect(LifecycleStage.fromApi('new'), LifecycleStage.newCustomer);
      // An unknown slug stays off the row rather than being printed raw.
      expect(LifecycleStage.fromApi('vip'), isNull);
      expect(LifecycleStage.fromApi(null), isNull);
    });

    test('favorite is read', () {
      final Contact c = contactFromJson(<String, dynamic>{
        ...row,
        'favorite': true,
      });
      expect(c.isFavorite, isTrue);
    });
  });

  group('the dashboard payload', () {
    // GET /dashboard, unedited. Note `series7d` and `agentQueue` sit beside
    // `stats`, not inside it.
    final Map<String, dynamic> body = <String, dynamic>{
      'success': true,
      'stats': <String, dynamic>{
        'openConversations': 29,
        'unassigned': 26,
        'assigned': 4,
        'totalContacts': 30,
        'newContactsToday': 0,
        'inboundToday': 0,
        'outboundToday': 0,
        'queued': 0,
        'avgFirstResponseSeconds': null,
      },
      'series7d': <dynamic>[
        <String, dynamic>{'date': '2026-07-26', 'inbound': 0, 'outbound': 0},
        <String, dynamic>{'date': '2026-07-27', 'inbound': 0, 'outbound': 0},
        <String, dynamic>{'date': '2026-07-28', 'inbound': 0, 'outbound': 0},
        <String, dynamic>{'date': '2026-07-29', 'inbound': 0, 'outbound': 0},
        <String, dynamic>{'date': '2026-07-30', 'inbound': 0, 'outbound': 2},
        <String, dynamic>{'date': '2026-07-31', 'inbound': 1, 'outbound': 2},
        <String, dynamic>{'date': '2026-08-01', 'inbound': 0, 'outbound': 0},
      ],
      'agentQueue': <dynamic>[
        <String, dynamic>{
          'uid': 'c6ac684e-f87d-4a9b-877c-92d73357fc92',
          'name': 'malek ahmed',
          'openConversations': 2,
        },
        <String, dynamic>{
          'uid': 'd57867fa-65f8-4e6c-8466-20cd70383145',
          'name': 'Clickalize Clickalize',
          'openConversations': 1,
        },
      ],
    };

    test('the week is not reported as silent when it had traffic', () {
      final DashboardSummary d = dashboardFromJson(body);

      expect(d.series7d, hasLength(7));
      // A day is `{inbound, outbound}`. There is no `count`, and reading one
      // parsed all seven days as zero — which the screen renders as "No
      // conversations this week" over a week with five messages in it.
      expect(d.series7d.every((DaySeriesPoint p) => p.count == 0), isFalse);
      expect(d.series7d[4].count, 2);
      expect(d.series7d[5].inbound, 1);
      expect(d.series7d[5].outbound, 2);
      expect(d.series7d[5].count, 3);
    });

    test('the queue is agents, and its uid is an agent uid', () {
      final DashboardSummary d = dashboardFromJson(body);

      expect(d.agentQueue, hasLength(2));
      expect(d.agentQueue.first.name, 'malek ahmed');
      expect(d.agentQueue.first.openConversations, 2);
      // Nothing in this payload is a conversation. Routing one of these uids
      // to /chats/:uid opened a conversation that does not exist.
      expect(
        d.agentQueue.first.agentUid,
        'c6ac684e-f87d-4a9b-877c-92d73357fc92',
      );
    });

    test('the stats still read from inside the envelope', () {
      final DashboardSummary d = dashboardFromJson(body);
      expect(d.openConversations, 29);
      expect(d.unassigned, 26);
      expect(d.totalContacts, 30);
      // Null, not absent — must not become a stray non-zero.
      expect(d.avgFirstResponseSeconds, 0);
    });
  });

  group('a note author is an object', () {
    test('the name is used, not the map', () {
      // `.toString()` on the author map printed the whole thing into the
      // author line: every card read `{uid: d57867fa-65f8-4e6...` and the
      // avatar took its initials from the opening brace.
      final InternalNote n = noteFromJson(<String, dynamic>{
        'uid': 'n1',
        'message': 'Wholesale client.',
        'author': <String, dynamic>{
          'uid': 'd57867fa-65f8-4e6c-8466-20cd70383145',
          'name': 'Clickalize Clickalize',
          'email': 'Clickalize@gmail.com',
        },
      });
      expect(n.authorName, 'Clickalize Clickalize');
      expect(n.authorName, isNot(contains('{')));
      expect(n.authorName, isNot(contains('uid')));
    });

    test('a first/last pair composes, and an email beats a uid', () {
      expect(
        noteFromJson(<String, dynamic>{
          'uid': 'n2',
          'author': <String, dynamic>{'firstName': 'Sara', 'lastName': 'Mahmoud'},
        }).authorName,
        'Sara Mahmoud',
      );
      expect(
        noteFromJson(<String, dynamic>{
          'uid': 'n3',
          'author': <String, dynamic>{'uid': 'x', 'email': 'sara@example.com'},
        }).authorName,
        'sara@example.com',
      );
      // A uid alone is not a name — better blank than a hex string.
      expect(
        noteFromJson(<String, dynamic>{
          'uid': 'n4',
          'author': <String, dynamic>{'uid': 'x'},
        }).authorName,
        isEmpty,
      );
    });

    test('a plain string author still works', () {
      expect(
        noteFromJson(<String, dynamic>{'uid': 'n5', 'author': 'Omar'}).authorName,
        'Omar',
      );
    });
  });
}
