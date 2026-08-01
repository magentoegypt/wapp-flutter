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

    test('the reply body is found on the row or inside __data', () {
      final BotReply flat = BotReply.fromJson(<String, dynamic>{
        'uid': 'b1',
        'name': 'A',
        'reply_text': 'On the row',
      });
      expect(flat.replyText, 'On the row');

      final BotReply nested = BotReply.fromJson(<String, dynamic>{
        'uid': 'b2',
        'name': 'B',
        '__data': <String, dynamic>{'reply_text': 'Inside data'},
      });
      expect(nested.replyText, 'Inside data');
    });

    test('a rich reply is not editable', () {
      // Saving one through the simple form would post message_type: simple and
      // replace its buttons with plain text.
      expect(BotMessageKindX.fromApi('interactive').isEditable, isFalse);
      expect(BotMessageKindX.fromApi('media').isEditable, isFalse);
      expect(BotMessageKindX.fromApi('simple').isEditable, isTrue);
    });

    test('a reply inside a flow reports itself as such', () {
      final BotReply r = BotReply.fromJson(<String, dynamic>{
        'uid': 'b3',
        'name': '',
        'bot_flow_uid': 'f1',
      });
      expect(r.isInFlow, isTrue);
    });

    test('a standalone reply is not in a flow', () {
      final BotReply r = BotReply.fromJson(<String, dynamic>{
        'uid': 'b4',
        'name': 'Solo',
      });
      expect(r.isInFlow, isFalse);
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
