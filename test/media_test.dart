import 'package:clickalize/features/inbox/data/media_repository.dart';
import 'package:clickalize/features/inbox/presentation/widgets/reaction_picker.dart';
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
  });
}
