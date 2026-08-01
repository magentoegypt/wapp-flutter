import 'package:clickalize/features/automation/data/bot_reply_repository.dart';
import 'package:clickalize/features/teams/data/team_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bot replies and teams.
///
/// The trigger rule is the one worth pinning: `welcome` and `ads_welcome` both
/// fire on a customer's *first* inbound message, so neither has a keyword to
/// match. The server drops `reply_trigger` for them and requires it for
/// everything else — a client that always sends it, or never does, fails one
/// half of that silently.
void main() {
  group('only the welcome triggers go without a keyword', () {
    test('welcome and ads_welcome need none', () {
      expect(BotTrigger.welcome.needsKeyword, isFalse);
      expect(BotTrigger.adsWelcome.needsKeyword, isFalse);
    });

    test('every matching trigger needs one', () {
      for (final BotTrigger t in <BotTrigger>[
        BotTrigger.is_,
        BotTrigger.startsWith,
        BotTrigger.endsWith,
        BotTrigger.containsWord,
        BotTrigger.contains,
      ]) {
        expect(t.needsKeyword, isTrue, reason: '${t.wire} matches on text');
      }
    });

    test('a welcome reply omits reply_trigger rather than sending empty', () {
      const BotReply r = BotReply(
        uid: '',
        name: 'Greeting',
        trigger: BotTrigger.welcome,
        replyText: 'Hello!',
      );
      final Map<String, dynamic> j = r.toJson();
      expect(j['trigger_type'], 'welcome');
      expect(j.containsKey('reply_trigger'), isFalse);
    });

    test('a keyword reply sends it', () {
      const BotReply r = BotReply(
        uid: '',
        name: 'Pricing',
        trigger: BotTrigger.contains,
        keyword: 'price',
        replyText: 'Here is our pricing.',
      );
      final Map<String, dynamic> j = r.toJson();
      expect(j['trigger_type'], 'contains');
      expect(j['reply_trigger'], 'price');
      expect(j['message_type'], 'simple');
    });
  });

  group('reading a bot reply back', () {
    test('an unknown trigger falls back to exact match, not welcome', () {
      // Falling back to `welcome` would turn a keyword reply into one that
      // fires on every new conversation.
      expect(BotTriggerX.fromApi('something_new'), BotTrigger.is_);
      expect(BotTriggerX.fromApi(null), BotTrigger.is_);
    });

    test('the live shape, verbatim', () {
      // Straight off the wire. Three things here read differently to their
      // names: the keyword is `trigger` (not `reply_trigger`, which is the
      // *write* name), membership of a flow is a boolean `inFlow`, and there
      // is no message-type field at all.
      final BotReply r = BotReply.fromJson(<String, dynamic>{
        'uid': '2afc1e30',
        'name': 'CIB',
        'triggerType': 'starts_with',
        'trigger': 'محتاج تواصل',
        'active': true,
        'inFlow': false,
        'replyText': 'اهلا بك{first_name}',
        'data': <String, dynamic>{
          'interaction_message': <String, dynamic>{
            'buttons': <String, dynamic>{'1': 'خدمة العملاء', '2': 'الدعم'},
            'header_type': 'image',
            'media_link': 'https://example.com/a.jpg',
            'interactive_type': 'button',
          },
        },
      });

      expect(r.trigger, BotTrigger.startsWith);
      expect(r.keyword, 'محتاج تواصل');
      expect(r.active, isTrue);
      expect(r.isInFlow, isFalse);
      expect(r.replyText, 'اهلا بك{first_name}');

      // The one that matters. This reply sends an image header and buttons;
      // opening it as editable and saving would post `message_type: simple`
      // with reply_text alone and destroy all of it.
      expect(r.messageKind, BotMessageKind.interactive);
      expect(r.messageKind.isEditable, isFalse);
    });

    test('the payload decides the kind, because no type field is sent', () {
      BotMessageKind kind(Map<String, dynamic>? m) =>
          BotMessageKindX.fromPayload(m);

      expect(kind(null), BotMessageKind.simple);
      expect(kind(<String, dynamic>{}), BotMessageKind.simple);

      // Nothing but a body is a plain reply and stays editable.
      expect(
        kind(<String, dynamic>{'body_text': 'hi', 'footer_text': ''}),
        BotMessageKind.simple,
      );

      for (final Map<String, dynamic> rich in <Map<String, dynamic>>[
        <String, dynamic>{'buttons': <String, dynamic>{'1': 'A'}},
        <String, dynamic>{'list_data': <String, dynamic>{'x': 1}},
        <String, dynamic>{'cta_url': 'https://example.com'},
        <String, dynamic>{'interactive_type': 'button'},
      ]) {
        expect(kind(rich), BotMessageKind.interactive, reason: '$rich');
      }

      expect(
        kind(<String, dynamic>{'media_link': 'https://example.com/a.jpg'}),
        BotMessageKind.media,
      );
      expect(
        kind(<String, dynamic>{'header_type': 'document'}),
        BotMessageKind.media,
      );

      // Empty strings are not a payload. The live rows send `footer_text: ""`
      // and `header_text: ""` on replies that carry neither, and treating those
      // as present would lock every simple reply out of its own editor.
      expect(
        kind(<String, dynamic>{
          'buttons': <String, dynamic>{},
          'media_link': '',
          'header_type': '',
          'cta_url': null,
          'list_data': null,
        }),
        BotMessageKind.simple,
      );

      // Interactive beats media — a button reply with an image header is still
      // a button reply.
      expect(
        kind(<String, dynamic>{
          'interactive_type': 'button',
          'media_link': 'https://example.com/a.jpg',
        }),
        BotMessageKind.interactive,
      );
    });

    test('an explicit message_type still wins if one ever appears', () {
      final BotReply r = BotReply.fromJson(<String, dynamic>{
        'uid': 'b1',
        'name': 'A',
        'message_type': 'media',
        'data': <String, dynamic>{
          'interaction_message': <String, dynamic>{'body_text': 'plain'},
        },
      });
      expect(r.messageKind, BotMessageKind.media);
    });

    test('the reply body is found on the row or inside the payload', () {
      final BotReply flat = BotReply.fromJson(<String, dynamic>{
        'uid': 'b1',
        'name': 'A',
        'replyText': 'On the row',
      });
      expect(flat.replyText, 'On the row');

      final BotReply nested = BotReply.fromJson(<String, dynamic>{
        'uid': 'b2',
        'name': 'B',
        'data': <String, dynamic>{
          'interaction_message': <String, dynamic>{'body_text': 'Inside data'},
        },
      });
      expect(nested.replyText, 'Inside data');
    });

    test('a reply inside a flow reports itself as such', () {
      expect(
        BotReply.fromJson(<String, dynamic>{'uid': 'b3', 'inFlow': true})
            .isInFlow,
        isTrue,
      );
      // The uid spelling still works, in case a payload carries it instead.
      expect(
        BotReply.fromJson(<String, dynamic>{'uid': 'b3', 'bot_flow_uid': 'f1'})
            .isInFlow,
        isTrue,
      );
      expect(
        BotReply.fromJson(<String, dynamic>{'uid': 'b4', 'inFlow': false})
            .isInFlow,
        isFalse,
      );
    });

    test('a switched-off reply is not reported as live', () {
      // `active` is absent on some payloads; absent means on, because that is
      // the state a reply is created in. Only an explicit false is off.
      expect(BotReply.fromJson(<String, dynamic>{'uid': 'b'}).active, isTrue);
      expect(
        BotReply.fromJson(<String, dynamic>{'uid': 'b', 'active': false}).active,
        isFalse,
      );
      expect(
        BotReply.fromJson(<String, dynamic>{'uid': 'b', 'active': 0}).active,
        isFalse,
      );
    });
  });

  group('teams', () {
    test('the list sends a count and the detail sends a roster', () {
      final WorkTeam fromList = WorkTeam.fromJson(<String, dynamic>{
        'uid': 't1',
        'title': 'Support',
        'memberCount': 4,
      });
      expect(fromList.displayCount, 4);
      expect(fromList.members, isEmpty);

      final WorkTeam fromDetail = WorkTeam.fromJson(<String, dynamic>{
        'uid': 't1',
        'title': 'Support',
        'members': <dynamic>[
          <String, dynamic>{'uid': 'u1', 'name': 'Sara'},
          <String, dynamic>{'uid': 'u2', 'name': 'Omar', 'role': 'Agent'},
        ],
      });
      // The detail carries no count, so the roster length stands in — otherwise
      // a team with members would report zero.
      expect(fromDetail.displayCount, 2);
      expect(fromDetail.members.last.role, 'Agent');
    });

    test('either spelling of the name is accepted', () {
      expect(
        WorkTeam.fromJson(<String, dynamic>{'uid': 't', 'name': 'Sales'}).title,
        'Sales',
      );
      expect(
        WorkTeam.fromJson(<String, dynamic>{'uid': 't', 'title': 'Sales'}).title,
        'Sales',
      );
    });

    test('a nameless member is dropped', () {
      final WorkTeam t = WorkTeam.fromJson(<String, dynamic>{
        'uid': 't1',
        'members': <dynamic>[
          <String, dynamic>{'uid': 'u1'},
          <String, dynamic>{'uid': 'u2', 'name': 'Omar'},
        ],
      });
      expect(t.members.single.name, 'Omar');
    });

    test('the title bounds are the ones the server enforces', () {
      expect(TeamLimits.titleMin, 2);
      expect(TeamLimits.titleMax, 255);
    });
  });
}
