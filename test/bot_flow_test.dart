import 'package:clickalize/core/network/api_client.dart';
import 'package:clickalize/features/automation/data/bot_flow_repository.dart';
import 'package:clickalize/features/automation/data/bot_reply_repository.dart';
import 'package:clickalize/features/inbox/domain/channel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bot flows, and the document rules the attach sheet enforces.
///
/// One thing dominates here: **the create endpoint ignores `active`.** A flow
/// asked for as running is saved stopped, and the API answers 201 either way —
/// so the app would show a live flow, the server would have it switched off,
/// and nobody would find out until a customer's message went unanswered. The
/// repository has to follow up with a PUT, and that second call is what these
/// tests exist to hold in place.

/// Records every call and answers with whatever was queued.
class _FakeApi implements ApiClient {
  final List<String> calls = <String>[];
  final List<Object?> bodies = <Object?>[];
  Map<String, dynamic> postResponse = <String, dynamic>{'uid': 'f-new'};

  @override
  Future<dynamic> post(
    String path, {
    Object? body,
    void Function(int, int)? onSendProgress,
    Duration? timeout,
  }) async {
    calls.add('POST $path');
    bodies.add(body);
    return postResponse;
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    calls.add('PUT $path');
    bodies.add(body);
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> delete(String path, {Object? body}) async {
    calls.add('DELETE $path');
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    calls.add('GET $path');
    return <String, dynamic>{};
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('creating a flow that should be running', () {
    test('posts without active, then puts to switch it on', () async {
      final _FakeApi api = _FakeApi();
      final String uid = await BotFlowRepositoryImpl(api).create(
        const BotFlow(
          uid: '',
          title: 'Onboarding',
          startTrigger: BotTrigger.contains,
          keyword: 'start',
          active: true,
        ),
      );

      expect(api.calls, <String>['POST /bot-flows', 'PUT /bot-flows/f-new']);
      expect(uid, 'f-new');

      // The create body must not carry `active` at all. Sending `false` would
      // read as a deliberate choice; sending `true` would be silently dropped.
      final Map<String, dynamic> created =
          api.bodies.first! as Map<String, dynamic>;
      expect(created.containsKey('active'), isFalse);
      // Snake_case in, camelCase out — the split bot replies already use.
      expect(created['trigger_type'], 'contains');
      expect(created['start_trigger'], 'start');

      final Map<String, dynamic> updated =
          api.bodies.last! as Map<String, dynamic>;
      expect(updated['active'], isTrue);
    });

    test('a stopped flow is one call, not two', () async {
      final _FakeApi api = _FakeApi();
      await BotFlowRepositoryImpl(api).create(
        const BotFlow(
          uid: '',
          title: 'Draft',
          startTrigger: BotTrigger.is_,
          keyword: 'hi',
        ),
      );
      expect(api.calls, <String>['POST /bot-flows']);
    });

    test('no uid back means no blind PUT', () async {
      // A PUT to /bot-flows/ would hit the collection, not a flow. Better to
      // return empty and let the screen say the flow was created but not
      // started than to send a request whose target does not exist.
      final _FakeApi api = _FakeApi()..postResponse = <String, dynamic>{};
      final String uid = await BotFlowRepositoryImpl(api).create(
        const BotFlow(
          uid: '',
          title: 'Orphan',
          startTrigger: BotTrigger.welcome,
          active: true,
        ),
      );
      expect(uid, isEmpty);
      expect(api.calls, <String>['POST /bot-flows']);
    });

    test('a welcome flow sends no trigger value', () {
      const BotFlow f = BotFlow(
        uid: '',
        title: 'Greeting',
        startTrigger: BotTrigger.welcome,
      );
      expect(f.toJson().containsKey('start_trigger'), isFalse);
      expect(f.toJson()['trigger_type'], 'welcome');
    });
  });

  group('reading a flow back', () {
    test('a tinyint 1 is running', () {
      // Some serialisers send 1/0 rather than true/false. `== true` alone would
      // show every running flow as stopped.
      for (final Object raw in <Object>[1, '1', 'true', true]) {
        expect(
          BotFlow.fromJson(<String, dynamic>{'uid': 'f', 'active': raw}).active,
          isTrue,
          reason: 'active: $raw',
        );
      }
      for (final Object? raw in <Object?>[0, '0', 'false', false, null]) {
        expect(
          BotFlow.fromJson(<String, dynamic>{'uid': 'f', 'active': raw}).active,
          isFalse,
          reason: 'active: $raw',
        );
      }
    });

    test('the trigger is triggerType, and startTrigger is the keyword', () {
      // The live row, verbatim. The two fields read the opposite way to what
      // their names suggest: `startTrigger` holds the matched text and
      // `triggerType` holds the enum. Reading them the other way round is
      // silent — every flow falls through to the `is` default and the list
      // says "Message is exactly" for all of them.
      final BotFlow f = BotFlow.fromJson(<String, dynamic>{
        'uid': 'cfc05338',
        'title': 'Ads Welcome Flow',
        'active': true,
        'triggerType': 'ads_welcome',
        'startTrigger': 'Test Ad',
        'createdAt': '2026-05-29 09:14:23',
      });

      expect(f.startTrigger, BotTrigger.adsWelcome);
      expect(f.keyword, 'Test Ad');
      expect(f.active, isTrue);
    });

    test('an absent step count stays unknown, not zero', () {
      final BotFlow counted = BotFlow.fromJson(<String, dynamic>{
        'uid': 'f',
        'stepCount': 3,
      });
      expect(counted.stepCount, 3);
      expect(counted.isKnownEmpty, isFalse);

      // The detail sends the replies and no count.
      final BotFlow listed = BotFlow.fromJson(<String, dynamic>{
        'uid': 'f',
        'botReplies': <dynamic>[<String, dynamic>{}, <String, dynamic>{}],
      });
      expect(listed.stepCount, 2);

      // The list sends neither. Defaulting that to 0 made every row claim the
      // flow was empty and put a warning pill on fully built flows.
      final BotFlow silent = BotFlow.fromJson(<String, dynamic>{'uid': 'f'});
      expect(silent.stepCount, isNull);
      expect(silent.isKnownEmpty, isFalse);

      // Zero, said explicitly, still means empty.
      expect(
        BotFlow.fromJson(<String, dynamic>{'uid': 'f', 'stepCount': 0})
            .isKnownEmpty,
        isTrue,
      );
    });

    test('either spelling of the name is accepted', () {
      expect(
        BotFlow.fromJson(<String, dynamic>{'uid': 'f', 'name': 'A'}).title,
        'A',
      );
      expect(
        BotFlow.fromJson(<String, dynamic>{'uid': 'f', 'title': 'A'}).title,
        'A',
      );
    });
  });

  group('documents per channel', () {
    test('Instagram takes PDF and nothing else', () {
      expect(MessageChannel.instagram.documentExtensions, <String>['pdf']);
      expect(MessageChannel.instagram.acceptsDocument('price.pdf'), isTrue);
      expect(MessageChannel.instagram.acceptsDocument('price.docx'), isFalse);
      expect(MessageChannel.instagram.acceptsDocument('price.xlsx'), isFalse);
    });

    test('WhatsApp takes the office set', () {
      for (final String name in <String>[
        'a.pdf',
        'a.doc',
        'a.docx',
        'a.xls',
        'a.xlsx',
        'a.ppt',
        'a.pptx',
        'a.txt',
        'a.csv',
      ]) {
        expect(MessageChannel.whatsapp.acceptsDocument(name), isTrue,
            reason: name);
      }
      expect(MessageChannel.whatsapp.acceptsDocument('a.exe'), isFalse);
    });

    test('case and odd names do not slip through', () {
      expect(MessageChannel.whatsapp.acceptsDocument('QUOTE.PDF'), isTrue);
      expect(MessageChannel.whatsapp.acceptsDocument('report.final.docx'),
          isTrue);
      // No extension, and a trailing dot — both would upload and then 422.
      expect(MessageChannel.whatsapp.acceptsDocument('README'), isFalse);
      expect(MessageChannel.whatsapp.acceptsDocument('trailing.'), isFalse);
    });
  });
}
