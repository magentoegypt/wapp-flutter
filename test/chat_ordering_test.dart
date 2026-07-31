import 'package:clickalize/features/inbox/data/conversation_repository.dart';
import 'package:clickalize/features/inbox/domain/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ordering regression cover for the chat thread.
///
/// The thread shipped rendering upside down: the mapper documented oldest-first
/// while the endpoint had moved to newest-first, and the view applied
/// `.reversed` on top of a `reverse: true` list. Two inversions that used to
/// cancel stopped cancelling, and nothing failed — no parser checks order.
///
/// These assert the boundary contract (newest-first out of the mapper)
/// independently of how the endpoint happens to sort today, so the same change
/// on the server cannot silently flip the UI again.
Map<String, dynamic> _msg(String uid, String at) => <String, dynamic>{
      'uid': uid,
      'body': uid,
      'isIncoming': true,
      'messagedAt': at,
    };

Map<String, dynamic> _payload(List<Map<String, dynamic>> messages) =>
    <String, dynamic>{
      'contact': <String, dynamic>{'uid': 'c1', 'name': 'Amira'},
      'messages': messages,
    };

void main() {
  group('chatThreadFromJson normalises to newest-first', () {
    test('reverses a payload that arrives oldest-first', () {
      final ChatThread t = chatThreadFromJson(
        'c1',
        _payload(<Map<String, dynamic>>[
          _msg('oldest', '2026-07-30T09:00:00Z'),
          _msg('middle', '2026-07-30T10:00:00Z'),
          _msg('newest', '2026-07-30T11:00:00Z'),
        ]),
      );

      expect(t.messages.first.uid, 'newest');
      expect(t.messages.last.uid, 'oldest');
    });

    test('leaves a payload that already arrives newest-first', () {
      final ChatThread t = chatThreadFromJson(
        'c1',
        _payload(<Map<String, dynamic>>[
          _msg('newest', '2026-07-30T11:00:00Z'),
          _msg('middle', '2026-07-30T10:00:00Z'),
          _msg('oldest', '2026-07-30T09:00:00Z'),
        ]),
      );

      expect(t.messages.first.uid, 'newest');
      expect(t.messages.last.uid, 'oldest');
    });

    test('keeps server order for messages sharing a timestamp', () {
      // Detect-and-reverse rather than sort, precisely so equal timestamps do
      // not shuffle between reloads.
      final ChatThread t = chatThreadFromJson(
        'c1',
        _payload(<Map<String, dynamic>>[
          _msg('a', '2026-07-30T10:00:00Z'),
          _msg('b', '2026-07-30T10:00:00Z'),
        ]),
      );

      expect(t.messages.map((ChatMessage m) => m.uid), <String>['a', 'b']);
    });

    test('undated messages pass through untouched', () {
      final ChatThread t = chatThreadFromJson(
        'c1',
        _payload(<Map<String, dynamic>>[
          <String, dynamic>{'uid': 'x', 'body': 'x', 'isIncoming': true},
          <String, dynamic>{'uid': 'y', 'body': 'y', 'isIncoming': true},
        ]),
      );

      expect(t.messages.map((ChatMessage m) => m.uid), <String>['x', 'y']);
    });

    test('an empty thread does not throw', () {
      final ChatThread t = chatThreadFromJson('c1', _payload(<Map<String, dynamic>>[]));
      expect(t.messages, isEmpty);
    });
  });
}
