import 'package:clickalize/features/inbox/data/media_repository.dart';
import 'package:clickalize/features/inbox/presentation/widgets/reaction_picker.dart';
import 'package:clickalize/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Media and reaction wire details.
///
/// Both of these are asymmetries rather than logic, which is exactly the kind
/// of thing that reads as correct and is not: `document` is spelled `file` on
/// the way in and `document` on the way out, and the send field is
/// `uploadedFileName` rather than the `mediaUrl` a reader would expect from
/// the WhatsApp docs.
void main() {
  group('MediaKind wire values', () {
    test('document is sent as "file", everything else as its own name', () {
      // The server normalises it back to `document` on the way out, so the two
      // directions genuinely differ and only this one is renamed.
      expect(MediaKind.document.wire, 'file');
      expect(MediaKind.image.wire, 'image');
      expect(MediaKind.video.wire, 'video');
      expect(MediaKind.audio.wire, 'audio');
    });

    test('every kind has a non-empty wire value', () {
      for (final MediaKind k in MediaKind.values) {
        expect(k.wire, isNotEmpty, reason: '${k.name} would send a blank type');
      }
    });
  });

  group('Instagram reactions', () {
    test('is a fixed set, not an open emoji picker', () {
      // Instagram accepts only these on a message. An arbitrary picker would
      // let an agent choose one that comes back rejected after the fact.
      expect(kInstagramReactions, isNotEmpty);
      expect(kInstagramReactions.length, 7);
      expect(kInstagramReactions, contains('❤️'));
      expect(kInstagramReactions, contains('👍'));
    });

    test('carries no duplicates', () {
      expect(kInstagramReactions.toSet().length, kInstagramReactions.length);
    });

    // On the device the heart came out flat dark navy while the other six were
    // full colour. Not a missing glyph — the reverse. Inter is the bundled app
    // font and Inter *has* a monochrome U+2764, and a primary font that can
    // render a codepoint wins outright, so the trailing U+FE0F requesting
    // emoji presentation never gets a say. The other six sit in the emoji
    // planes Inter does not cover, so they fall through to the system font,
    // which is why it read as one odd heart rather than a font-resolution rule.
    //
    // Nothing about this is visible in review — the wrong version is the
    // shorter, more obvious `TextStyle(fontSize: 26)`. So the guard is that the
    // emoji must not resolve to the app font.
    testWidgets('emoji are not drawn in the bundled app font',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(fontFamily: 'Inter'),
          home: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showReactionPicker(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      for (final String emoji in kInstagramReactions) {
        final TextStyle? style = tester.widget<Text>(find.text(emoji)).style;
        expect(
          style?.fontFamily,
          isNotNull,
          reason: '$emoji would inherit Inter and lose emoji presentation',
        );
        expect(style!.fontFamily, isNot('Inter'));
      }
    });
  });
}
