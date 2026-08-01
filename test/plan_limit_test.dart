import 'package:clickalize/core/error/failure.dart';
import 'package:clickalize/core/widgets/async_value_view.dart';
import 'package:clickalize/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two 403s must not look the same.
///
/// The API gates by permission *and* by subscription plan, and both refusals
/// come back as 403. The client already tells them apart — a plan refusal
/// carries a `module` key — but for a while nothing downstream used that: both
/// landed in the same red error box with the same Retry button.
///
/// That is the worse half of the bug. A permission problem is fixed by an
/// admin; a plan problem is fixed by an upgrade, and no amount of retrying
/// moves either. Offering Retry on a refusal that is guaranteed to repeat
/// reads as "the app is flaky" rather than "this is switched off".
Future<void> _pump(WidgetTester tester, Object error) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: AsyncValueView<int>(
          value: AsyncValue<int>.error(error, StackTrace.empty),
          onRetry: () {},
          builder: (int v) => Text('$v'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a plan refusal offers no retry', (WidgetTester tester) async {
    await _pump(
      tester,
      const PlanLimitFailure('Bot replies are not in your plan.', 'bot_reply'),
    );

    expect(find.byType(PlanLimitMessage), findsOneWidget);
    expect(find.text('Bot replies are not in your plan.'), findsOneWidget);
    expect(find.text('Not included in your plan'), findsOneWidget);
    // The whole point: no button, because pressing it could only fail again.
    expect(find.byType(OutlinedButton), findsNothing);
    // And not the red error treatment.
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('a permission refusal keeps its retry', (WidgetTester t) async {
    await _pump(t, const ForbiddenFailure());

    expect(find.byType(PlanLimitMessage), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
  });

  testWidgets('a non-Failure error never leaks its toString', (
    WidgetTester tester,
  ) async {
    // A raw exception escaping the data layer used to be printed verbatim.
    await _pump(tester, StateError('Bad state: null check on a null value'));

    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
  });
}
