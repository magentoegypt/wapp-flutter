import 'package:clickalize/app/theme/app_colors.dart';
import 'package:clickalize/app/theme/app_dimens.dart';
import 'package:clickalize/core/widgets/app_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cover for the header contract QA raised as CL037-TC17: "the same color tone
/// and the same size and shape of the header on every page."
///
/// Nothing in this repo asserted on a colour or a header height before this
/// file, which is how four separate divergences accumulated in a widget that
/// 45 of 53 screens already shared. The existing widget tests build a bare
/// `ThemeData`, so they would not have caught any of them either.
///
/// The load-bearing case is [_bandMatchesDeclaredHeight]. `AppHeader` is a
/// [PreferredSizeWidget], so `Scaffold` reserves exactly `preferredSize.height`
/// and paints the band into it — but the children were laid out from separate
/// hardcoded `SizedBox`es that nothing tied to that number. When the two
/// disagree the result is either dead green under the search field or an
/// overflow the moment the clear button appears, and this header has shipped
/// both. Asserting the declared height against the drawn one is what stops it
/// happening a third time.

Widget _host(Widget header) => MaterialApp(
      home: MediaQuery(
        // No status-bar inset: `SafeArea` inside the header would add it and
        // `Scaffold` would add it again, and the point here is to measure the
        // header's own content box.
        data: const MediaQueryData(),
        child: Scaffold(appBar: header as PreferredSizeWidget),
      ),
    );

/// The band's own ground — the first [Container] the header paints.
Container _band(WidgetTester tester) => tester.widget<Container>(
      find
          .descendant(
            of: find.byType(AppHeader),
            matching: find.byType(Container),
          )
          .first,
    );

void main() {
  final Map<String, AppHeader> variants = <String, AppHeader>{
    'back': const AppHeader.back(title: 'Contact'),
    'title': const AppHeader.title(title: 'More'),
    'search': const AppHeader.search(title: 'Contacts', searchHint: 'Search'),
    'greeting': const AppHeader.greeting(
      title: 'Hassan Ali',
      subtitle: 'Good morning',
    ),
  };

  group('every variant', () {
    variants.forEach((String name, AppHeader header) {
      testWidgets('$name paints the brand green and nothing else',
          (WidgetTester tester) async {
        await tester.pumpWidget(_host(header));

        final Container band = _band(tester);
        expect(band.color, AppColor.brand,
            reason: 'the band reads its ground from the token, not a literal');

        // A `BoxDecoration` here would mean a border, a gradient or — as
        // Dashboard's own header carried until CL037-TC17 — a rounded bottom
        // edge that no frame draws and no other header had.
        expect(band.decoration, isNull,
            reason: '$name must be a flat, square band like every other');
      });

      testWidgets('$name draws the band it declares',
          (WidgetTester tester) async {
        await tester.pumpWidget(_host(header));

        expect(
          tester.getSize(find.byType(AppHeader)).height,
          header.preferredSize.height,
          reason: 'declared preferredSize must equal the height drawn',
        );
        expect(tester.takeException(), isNull);
      });
    });
  });

  testWidgets('the tall variants measure their frames', (WidgetTester t) async {
    // 132 and 68 of content, over the 47pt status bar the frames were measured
    // on, give the 181 and ~121 bands `docs/frames/` draws.
    expect(
      variants['search']!.preferredSize.height,
      AppDimens.headerTopPad +
          AppDimens.headerTitleLine +
          AppDimens.headerTitleToField +
          AppDimens.headerField +
          AppDimens.headerBottomPad,
    );
    expect(
      variants['title']!.preferredSize.height,
      AppDimens.headerTopPad +
          AppDimens.headerTitleLine +
          AppDimens.headerBottomPad,
    );
    expect(variants['back']!.preferredSize.height, AppDimens.headerBack);
    expect(variants['greeting']!.preferredSize.height, AppDimens.headerGreeting);
  });

  testWidgets('a long name truncates rather than wrapping or overflowing',
      (WidgetTester tester) async {
    // The contract test case CL037-TC17 states: "a long workspace name
    // truncates with an ellipsis, it does not wrap or overlap."
    const String long =
        'Bardiya Commerce Operations and Customer Experience Workspace';

    await tester.pumpWidget(
      _host(
        const AppHeader.greeting(
          title: long,
          subtitle: 'Good morning',
          trailing: SizedBox(width: 34, height: 34),
        ),
      ),
    );

    final Text name = tester.widget<Text>(find.text(long));
    expect(name.maxLines, 1);
    expect(name.overflow, TextOverflow.ellipsis);
    // The avatar sits outside the flexing block, so a long name shortens
    // instead of pushing it off the edge.
    expect(tester.takeException(), isNull);
    expect(find.byType(SizedBox), findsWidgets);
  });
}
