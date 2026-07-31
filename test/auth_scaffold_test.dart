import 'package:clickalize/features/auth/presentation/widgets/auth_scaffold.dart';
import 'package:clickalize/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keyboard-overflow cover for the signed-out chrome.
///
/// Login shipped painting `BOTTOM OVERFLOWED BY 125 PIXELS` the moment the
/// keyboard opened: the hero took `Expanded` and the sheet its natural height,
/// so nothing in the column could give up space when the viewport shrank. It
/// looked correct in every screenshot taken at rest, which is why it survived,
/// and it affected all three signed-out screens at once because they share
/// this scaffold.
///
/// The two cases below are the two that matter and pull in opposite
/// directions: with room, the sheet must still sit flush at the bottom; without
/// room, the page must scroll instead of overflowing. A fix that only satisfies
/// one of them is the obvious wrong turn here — dropping `Expanded` stops the
/// overflow and leaves the sheet floating mid-screen.

/// A form roughly the height of Login's: two fields, a link and a button.
Widget _form() => const Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AuthFieldLabel('Email'),
        TextField(),
        SizedBox(height: 14),
        AuthFieldLabel('Password'),
        TextField(),
        SizedBox(height: 10),
        Text('Forgot password?'),
        SizedBox(height: 14),
        SizedBox(height: 48, width: double.infinity, child: Placeholder()),
      ],
    );

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AuthScaffold(child: _form()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('does not overflow when the keyboard leaves a short viewport',
      (WidgetTester tester) async {
    // 360x340 is about what a mid-size phone has left above an open keyboard,
    // and is shorter than the hero plus the form can be drawn in.
    await _pumpAt(tester, const Size(360, 340));

    // An overflow is reported as an exception rather than a failed frame, so
    // it passes silently unless it is asked for.
    expect(
      tester.takeException(),
      isNull,
      reason: 'the signed-out chrome overflowed instead of scrolling',
    );
  });

  testWidgets('keeps the sheet flush to the bottom when there is room',
      (WidgetTester tester) async {
    await _pumpAt(tester, const Size(360, 800));
    expect(tester.takeException(), isNull);

    // The scroll view must not collapse the layout to its intrinsic height:
    // the hero still fills what is left and the sheet still lands on the
    // bottom edge, which is what makes this read as a sheet at all.
    final Rect sheet = tester.getRect(
      find.ancestor(
        of: find.byType(AuthFieldLabel).first,
        matching: find.byType(DecoratedBox),
      ).last,
    );
    expect(sheet.bottom, closeTo(800, 1));
  });
}
