import 'package:clickalize/core/util/contact_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Display formatting on Contact detail.
///
/// `wa_id` is stored bare — country code first, no `+`, no separators — which
/// is what the send endpoints want and what nobody wants to read. The frame
/// shows `+20 102 998 1200`. These pin the transformation so a "tidy-up" of
/// the grouping cannot quietly change digits.
void main() {
  group('phone', () {
    test('groups a full international number the way the frame does', () {
      expect(formatPhone('201029981200'), '+20 102 998 1200');
      expect(formatPhone('201020104267'), '+20 102 010 4267');
    });

    test('the code boundary is inferred from length, not known', () {
      // Exact for Egypt (20 + 10 digits), which is the frame's example and
      // this workspace's market. A three-digit code with a shorter subscriber
      // number splits a digit early — asserted here so the limitation is
      // recorded rather than discovered, and because the digits are still all
      // present and in order, which is the part that matters.
      expect(formatPhone('971585400883'), '+97 158 540 0883');
    });

    test('a number with no room for a code just gains a plus', () {
      expect(formatPhone('1029981200'), '+1029981200');
    });

    test('anything already formatted is left alone', () {
      // Never mangle a value that arrived in some other shape.
      expect(formatPhone('+20 102 998 1200'), '+20 102 998 1200');
      expect(formatPhone('+201029981200'), '+201029981200');
    });

    test('empty and nonsense pass through untouched', () {
      expect(formatPhone(''), '');
      expect(formatPhone('n/a'), 'n/a');
      // Too short to be a number with a country code.
      expect(formatPhone('12345'), '12345');
    });

    test('no digit is ever added or dropped', () {
      const List<String> raws = <String>[
        '201029981200',
        '971585400883',
        '918200449201',
      ];
      for (final String raw in raws) {
        final String shown = formatPhone(raw);
        expect(shown.replaceAll(RegExp(r'[^\d]'), ''), raw);
      }
    });
  });

  group('language', () {
    test('a wire code becomes a name', () {
      expect(languageName('en'), 'English');
      expect(languageName('ar'), 'العربية');
    });

    test('a regional code falls back to its base language', () {
      expect(languageName('en-US'), 'English');
      expect(languageName('ar_EG'), 'العربية');
    });

    test('an unknown code reads as a code, not as a wrong language', () {
      // Guessing here would put a confidently wrong language on the screen.
      expect(languageName('xx'), 'XX');
    });

    test('absent stays absent so the row is omitted', () {
      expect(languageName(null), isNull);
      expect(languageName('  '), isNull);
    });
  });
}
