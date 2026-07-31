import 'package:clickalize/core/network/envelope.dart';
import 'package:flutter_test/flutter_test.dart';

/// Envelope-reading cover.
///
/// This exists because getting it wrong is silent. Reading a nested field from
/// the root does not throw — it yields null and falls to whatever default the
/// model declares. That is exactly how a workspace owner was shown the *agent*
/// view of History access: the payload nested `isVendorAdmin: true` under
/// `historyAccess`, the repository read it from the root, and `?? false`
/// finished the job. Nothing failed; the screen was simply wrong.
void main() {
  group('envelopeRecord', () {
    test('reaches a record nested under its domain key', () {
      // The shape that caused the bug, verified from a real response.
      final Map<String, dynamic> body = <String, dynamic>{
        'success': true,
        'historyAccess': <String, dynamic>{
          'isVendorAdmin': true,
          'revealFullHistory': true,
          'pending': <dynamic>[],
        },
      };

      final Map<String, dynamic> r = envelopeRecord(body, 'historyAccess');
      expect(r['isVendorAdmin'], isTrue);
      expect(r['revealFullHistory'], isTrue);
    });

    test('falls back to data, then to the body itself', () {
      expect(
        envelopeRecord(<String, dynamic>{
          'success': true,
          'data': <String, dynamic>{'x': 1},
        }, 'thing')['x'],
        1,
      );
      // A flat answer must keep working rather than resolving to empty.
      expect(envelopeRecord(<String, dynamic>{'x': 2}, 'thing')['x'], 2);
    });

    test('a null or non-map body yields an empty map, not a throw', () {
      expect(envelopeRecord(null, 'thing'), isEmpty);
      expect(envelopeRecord('nonsense', 'thing'), isEmpty);
    });

    test('a non-map value under the key is ignored', () {
      // Guards the case that would otherwise crash on cast.
      final Map<String, dynamic> body = <String, dynamic>{
        'thing': <dynamic>[1, 2],
        'x': 3,
      };
      expect(envelopeRecord(body, 'thing')['x'], 3);
    });
  });

  group('envelopeRows', () {
    test('reaches a list under its domain key', () {
      final List<Map<String, dynamic>> rows = envelopeRows(<String, dynamic>{
        'success': true,
        'calls': <dynamic>[
          <String, dynamic>{'uid': 'a'},
          <String, dynamic>{'uid': 'b'},
        ],
      }, 'calls');
      expect(rows.map((Map<String, dynamic> r) => r['uid']), <String>['a', 'b']);
    });

    test('accepts a bare list, and empties safely', () {
      expect(envelopeRows(<dynamic>[<String, dynamic>{'uid': 'a'}], 'calls').length, 1);
      expect(envelopeRows(<String, dynamic>{'success': true}, 'calls'), isEmpty);
      expect(envelopeRows(null, 'calls'), isEmpty);
    });

    test('drops non-map entries rather than throwing', () {
      final List<Map<String, dynamic>> rows = envelopeRows(<String, dynamic>{
        'calls': <dynamic>[<String, dynamic>{'uid': 'a'}, 'junk', 7],
      }, 'calls');
      expect(rows.length, 1);
    });
  });
}
