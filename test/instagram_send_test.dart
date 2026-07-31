import 'package:clickalize/features/inbox/data/instagram_repository.dart';
import 'package:clickalize/features/inbox/presentation/screens/instagram_send_screen.dart';
import 'package:clickalize/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Covers the one thing the API will not do for us.
///
/// Meta trims over-long titles and answers 200, so every assertion here about a
/// refused send is guarding against a message that would otherwise reach the
/// customer shortened, with nothing in the app or the response saying so.
class _FakeIgRepo implements InstagramRepository {
  List<IgQuickReply>? sentQuickReplies;
  String? sentMessage;
  List<IgButton>? sentButtons;
  List<IgCard>? sentCards;
  List<IgTemplate> saved = <IgTemplate>[];

  @override
  Future<void> react({
    required String contactUid,
    required String messageUid,
    required String emoji,
  }) async {}

  @override
  Future<void> sendQuickReplies({
    required String contactUid,
    required String message,
    required List<IgQuickReply> quickReplies,
  }) async {
    sentMessage = message;
    sentQuickReplies = quickReplies;
  }

  @override
  Future<void> sendButtonTemplate({
    required String contactUid,
    required String message,
    required List<IgButton> buttons,
  }) async {
    sentMessage = message;
    sentButtons = buttons;
  }

  @override
  Future<void> sendGenericTemplate({
    required String contactUid,
    required List<IgCard> elements,
  }) async {
    sentCards = elements;
  }

  @override
  Future<List<IgTemplate>> templates(IgTemplateKind kind) async => saved;
}

Future<void> _pump(WidgetTester tester, _FakeIgRepo repo) async {
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('root')),
        routes: <RouteBase>[
          GoRoute(
            path: 'ig',
            builder: (_, __) => const InstagramSendScreen(contactUid: 'c1'),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        instagramRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/ig');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders and refuses an empty draft', (WidgetTester t) async {
    final _FakeIgRepo repo = _FakeIgRepo();
    await _pump(t, repo);

    expect(find.text('Instagram message'), findsOneWidget);
    expect(
      find.textContaining('Instagram trims over-long text'),
      findsOneWidget,
    );

    await t.tap(find.text('Send'));
    await t.pumpAndSettle();

    expect(find.text('Write a message.'), findsOneWidget);
    expect(find.text('Every option needs a title.'), findsOneWidget);
    expect(repo.sentQuickReplies, isNull);
  });

  testWidgets('sends a valid quick reply set', (WidgetTester t) async {
    final _FakeIgRepo repo = _FakeIgRepo();
    await _pump(t, repo);

    await t.enterText(find.byType(TextFormField).at(0), 'Pick one');
    await t.enterText(find.byType(TextFormField).at(1), 'Track order');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();

    expect(repo.sentMessage, 'Pick one');
    expect(repo.sentQuickReplies?.single.title, 'Track order');
  });

  testWidgets('maxLength stops typing past the title cap',
      (WidgetTester t) async {
    final _FakeIgRepo repo = _FakeIgRepo();
    await _pump(t, repo);

    await t.enterText(
      find.byType(TextFormField).at(1),
      'Track my order right now please',
    );
    await t.pumpAndSettle();

    final TextFormField field =
        t.widget<TextFormField>(find.byType(TextFormField).at(1));
    expect(field.controller!.text.length, IgLimits.title);
    // Live counter.
    expect(find.text('20/20'), findsOneWidget);
  });

  testWidgets('adding past the cap is refused with the reason',
      (WidgetTester t) async {
    final _FakeIgRepo repo = _FakeIgRepo();
    await _pump(t, repo);

    for (int i = 0; i < IgLimits.maxQuickReplies + 1; i++) {
      await t.ensureVisible(find.text('Add'));
      await t.pumpAndSettle();
      await t.tap(find.text('Add'));
      await t.pumpAndSettle();
    }

    expect(find.text('Instagram allows at most 13.'), findsOneWidget);
  });

  testWidgets('a template with an over-long title is caught on send',
      (WidgetTester t) async {
    final _FakeIgRepo repo = _FakeIgRepo()
      ..saved = <IgTemplate>[
        const IgTemplate(
          uid: 't1',
          name: 'Order help',
          kind: IgTemplateKind.quickReply,
          payload: <String, dynamic>{
            'message': 'How can we help?',
            'quickReplies': <dynamic>[
              <String, dynamic>{
                'title': 'Track my order right now',
                'payload': 'TRACK',
                'contentType': 'text',
              },
            ],
          },
        ),
      ];
    await _pump(t, repo);

    await t.tap(find.text('Use a saved template'));
    await t.pumpAndSettle();
    await t.tap(find.text('Order help'));
    await t.pumpAndSettle();

    // Prefilled straight from the payload, over-length and all.
    expect(find.text('How can we help?'), findsOneWidget);
    expect(find.text('Track my order right now'), findsOneWidget);

    await t.tap(find.text('Send'));
    await t.pumpAndSettle();

    expect(
      find.textContaining('Titles are cut at 20 characters'),
      findsOneWidget,
    );
    expect(repo.sentQuickReplies, isNull);
  });

  testWidgets('cards send with their 80-char text and buttons',
      (WidgetTester t) async {
    final _FakeIgRepo repo = _FakeIgRepo();
    await _pump(t, repo);

    await t.tap(find.text('Cards'));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextFormField).at(0), 'Autumn jacket');
    await t.enterText(find.byType(TextFormField).at(1), 'Water resistant');
    // The card's own Add, not the one that adds another card.
    await t.ensureVisible(find.text('Add').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Add').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).at(3), 'Buy');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();

    expect(repo.sentCards?.single.title, 'Autumn jacket');
    expect(repo.sentCards?.single.subtitle, 'Water resistant');
    expect(repo.sentCards?.single.buttons.single.title, 'Buy');
    expect(repo.sentCards?.single.buttons.single.type, 'postback');
  });
}
