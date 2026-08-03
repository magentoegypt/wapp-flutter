import 'package:clickalize/features/reports/data/report_repository.dart';
import 'package:clickalize/features/reports/domain/reports.dart';
import 'package:flutter_test/flutter_test.dart';

/// The four reporting payloads, pinned against the shapes the backend actually
/// sends.
///
/// These mappers are deliberately total — an unrecognised payload yields an
/// empty report rather than throwing. That is right for the UI and wrong for
/// review: a key-name mistake produces "no data for this window", which is
/// indistinguishable from a quiet week. Every screen-blanking bug in this app so
/// far has hidden in exactly that gap, so the shapes are asserted here instead
/// of trusted.
///
/// Fixtures follow `ReportApiController` and the four engine helpers it wraps.
void main() {
  group('conversational', () {
    // Trimmed to the keys under test; the real payload carries all 22.
    final Map<String, dynamic> payload = <String, dynamic>{
      'success': true,
      'window': 'W',
      'report': <String, dynamic>{
        'allRead': 1204,
        'allReadOld': 12,
        'avWaitTime': 7,
        'avWaitTimeOld': -30,
        'opConvs': 88,
        'opConvsOld': 0,
        'clsConvs': 71,
        'newCustomers': 14,
        'returningCustomers': 52,
        'allConv': 159,
        'missed': 3,
        'chatTransfer': 9,
        'chatDuration': 5400,
        'allReadList': <String, dynamic>{
          'xData': <String>['1 August', '2 August'],
          'yData': <int>[600, 604],
        },
        'convPerAgent': <String, dynamic>{
          'xData': <String>['Amira', 'Karim', 'Sara'],
          'yData': <int>[40, 30, 18],
        },
      },
      'agents': <Map<String, dynamic>>[
        <String, dynamic>{'uid': 'u1', 'name': 'Amira'},
        <String, dynamic>{'uid': null, 'name': 'Ghost'},
      ],
    };

    test('per-agent metrics survive the parallel-array shape', () {
      // THE trap in this payload. The console feeds xData/yData straight to a
      // chart library, so there are no row objects to read. A mapper expecting
      // a list finds none, returns empty, and the screen reports that nobody
      // handled a conversation all week.
      final ConversationalReport r = conversationalFromJson(payload);

      expect(r.conversationsPerAgent.rows, hasLength(3));
      expect(r.conversationsPerAgent.rows.first.name, 'Amira');
      expect(r.conversationsPerAgent.rows.first.value, 40);
      expect(r.conversationsPerAgent.max, 40);
    });

    test('mismatched array lengths clamp rather than pad', () {
      // A name with a fabricated zero beside it is worse than an absent row —
      // it reads as a measured result.
      final ConversationalReport r =
          conversationalFromJson(<String, dynamic>{
        'report': <String, dynamic>{
          'convPerAgent': <String, dynamic>{
            'xData': <String>['Amira', 'Karim', 'Sara'],
            'yData': <int>[40],
          },
        },
      });
      expect(r.conversationsPerAgent.rows, hasLength(1));
    });

    test('`…Old` is a percent delta, not the previous value', () {
      // The engine runs percentageDifference() before serialising. Rendering
      // `allReadOld` as "last period: 12" beside a current 1204 would state a
      // comparison that was never made.
      final ConversationalReport r = conversationalFromJson(payload);

      expect(r.received.value, 1204);
      expect(r.received.changePercent, 12);
      expect(r.received.isUp, isTrue);
    });

    test('a missing delta is absent, not zero', () {
      // `clsConvs` has no `clsConvsOld` in the fixture. Null means "nothing was
      // compared"; 0 would claim the figure held steady.
      final ConversationalReport r = conversationalFromJson(payload);

      expect(r.closed.value, 71);
      expect(r.closed.changePercent, isNull);
      expect(r.closed.hasChange, isFalse);

      // A real zero is a real answer and must still be distinguishable.
      expect(r.opened.changePercent, 0);
      expect(r.opened.hasChange, isFalse);
    });

    test('a falling wait time reads as an improvement', () {
      final ConversationalReport r = conversationalFromJson(payload);
      expect(r.avgWaitMinutes.changePercent, -30);
      expect(r.avgWaitMinutes.isDown, isTrue);
    });

    test('trend lists share the chart shape', () {
      final ConversationalReport r = conversationalFromJson(payload);
      expect(r.receivedTrend, hasLength(2));
      expect(r.receivedTrend.first.label, '1 August');
      expect(r.receivedTrend.first.value, 600);
    });

    test('the window is read from the envelope, beside `report`', () {
      expect(conversationalFromJson(payload).window, ReportWindow.week);
    });

    test('an agent with no uid is dropped from the filter', () {
      // It could be selected but never sent, so the filter would silently do
      // nothing.
      final ConversationalReport r = conversationalFromJson(payload);
      expect(r.agents, hasLength(1));
      expect(r.agents.first.uid, 'u1');
    });

    test('other counts come from their own keys', () {
      final ConversationalReport r = conversationalFromJson(payload);
      expect(r.totalConversations, 159);
      expect(r.missed, 3);
      expect(r.chatTransfers, 9);
      expect(r.newCustomers, 14);
      expect(r.returningCustomers, 52);
      expect(r.chatDurationSeconds, 5400);
    });
  });

  group('pause reasons', () {
    final Map<String, dynamic> payload = <String, dynamic>{
      'report': <String, dynamic>{
        'agents': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'Amira',
            'total_seconds': 5400,
            'sessions': 4,
            'total_human': '1h 30m',
            'rows': <Map<String, dynamic>>[
              <String, dynamic>{
                'status': 'away',
                'label': 'Lunch',
                'sessions': 2,
                'total_seconds': 3600,
                'total_human': '1h',
              },
            ],
          },
        ],
        'reasonTotals': <Map<String, dynamic>>[
          <String, dynamic>{'label': 'Lunch', 'seconds': 3600, 'human': '1h'},
        ],
        'grand': <String, dynamic>{
          'seconds': 5400,
          'human': '1h 30m',
          'sessions': 4,
        },
      },
    };

    test('reads the snake_case row keys and the server rendering', () {
      final PauseReasonReport r = pauseReasonsFromJson(payload);

      expect(r.agents, hasLength(1));
      expect(r.agents.first.totalHuman, '1h 30m');
      expect(r.agents.first.rows.first.totalSeconds, 3600);
      // `label` falls back to the status server-side, so a pause with no
      // reason still names itself. Reading `reason` would have been blank on
      // every plain away/busy toggle.
      expect(r.agents.first.rows.first.label, 'Lunch');
      expect(r.grandHuman, '1h 30m');
      expect(r.grandSessions, 4);
    });
  });

  group('quality reviews', () {
    test('reads scores and falls back to the username for a nameless author',
        () {
      final QualityReport r = qualityFromJson(<String, dynamic>{
        'report': <String, dynamic>{
          'agents': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'Amira',
              'reviews': 6,
              'avg_score': 4.25,
            },
          ],
          'recent': <Map<String, dynamic>>[
            <String, dynamic>{
              'score': 5,
              'comment': 'Handled the refund well',
              'agent_name': '',
              'agent_username': 'amira',
              'reviewer_name': 'Mona Adel',
              'created_at': '2026-08-01 10:00:00',
            },
          ],
          'totalReviews': 6,
          'avgScore': 4.25,
        },
      });

      expect(r.agents.first.averageScore, 4.25);
      expect(r.recent.first.agentName, 'amira');
      expect(r.recent.first.reviewerName, 'Mona Adel');
      expect(r.recent.first.createdAt, isNotNull);
    });

    test('an empty window has a null average, not 0.0', () {
      // "0.0" would read as everyone having been reviewed and scored zero.
      final QualityReport r = qualityFromJson(<String, dynamic>{
        'report': <String, dynamic>{'totalReviews': 0, 'avgScore': null},
      });
      expect(r.averageScore, isNull);
      expect(r.isEmpty, isTrue);
    });
  });

  group('agent targets', () {
    final Map<String, dynamic> payload = <String, dynamic>{
      'report': <String, dynamic>{
        'year': 2026,
        'month': 8,
        'monthLabel': 'August 2026',
        'rows': <Map<String, dynamic>>[
          <String, dynamic>{
            'user_uid': 'u1',
            'name': 'Amira',
            'targets': <String, dynamic>{
              'leads': 100,
              'orders': null,
              'response_time': 5,
              'revenue': null,
              'csat': null,
            },
            'actuals': <String, dynamic>{
              'leads': 62,
              'orders': 0,
              'revenue': 0,
              'response_time': null,
              'csat': null,
            },
          },
          <String, dynamic>{
            'user_uid': 'u2',
            'name': 'Karim',
            'targets': <String, dynamic>{},
            'actuals': <String, dynamic>{'leads': 4},
          },
        ],
      },
    };

    test('an unset target stays null and is not a met zero', () {
      // AgentTargetModel returns null for every column never filled in.
      // Coercing that to 0 would draw "0 / 0" — a target the agent has
      // already met — for a target nobody set.
      final AgentTargetsReport r = agentTargetsFromJson(payload);

      expect(r.rows.first.targets.leads, 100);
      expect(r.rows.first.targets.orders, isNull);
      expect(r.rows.first.targets.revenue, isNull);
    });

    test('an agent with no targets at all is flagged', () {
      final AgentTargetsReport r = agentTargetsFromJson(payload);
      expect(r.rows.first.hasNoTargets, isFalse);
      expect(r.rows[1].hasNoTargets, isTrue);
    });

    test('this report does carry a uid, unlike the other two', () {
      expect(agentTargetsFromJson(payload).rows.first.agentUid, 'u1');
    });

    test('the server month label is kept verbatim', () {
      final AgentTargetsReport r = agentTargetsFromJson(payload);
      expect(r.monthLabel, 'August 2026');
      expect(r.year, 2026);
      expect(r.month, 8);
    });
  });

  group('envelope', () {
    test('fields hoisted to the root are still found', () {
      // All four answer {success, report:{...}}. The root fallback exists so a
      // later tidy-up that flattens the envelope cannot blank every screen in
      // this module at once.
      final PauseReasonReport r = pauseReasonsFromJson(<String, dynamic>{
        'success': true,
        'grand': <String, dynamic>{'human': '2h', 'sessions': 9},
      });
      expect(r.grandHuman, '2h');
      expect(r.grandSessions, 9);
    });

    test('an unrecognised payload is empty rather than an exception', () {
      expect(conversationalFromJson(<String, dynamic>{}).received.value, 0);
      expect(pauseReasonsFromJson(<String, dynamic>{}).isEmpty, isTrue);
      expect(qualityFromJson(<String, dynamic>{}).isEmpty, isTrue);
      expect(agentTargetsFromJson(<String, dynamic>{}).isEmpty, isTrue);
    });
  });

  group('month paging', () {
    test('stepping back from January carries the year', () {
      expect(const TargetMonth(2026, 1).shift(-1), const TargetMonth(2025, 12));
      expect(const TargetMonth(2026, 12).shift(1), const TargetMonth(2027, 1));
      expect(const TargetMonth(2026, 8).shift(-8), const TargetMonth(2025, 12));
    });
  });

  group('query', () {
    test('clearing the agent filter is distinct from leaving it alone', () {
      // The usual copyWith ambiguity, and here the two readings differ by a
      // whole workspace of data.
      const ConversationalQuery q =
          ConversationalQuery(window: ReportWindow.week, agentUid: 'u1');

      expect(q.copyWith(window: ReportWindow.day).agentUid, 'u1');
      expect(q.copyWith(agentUid: null).agentUid, isNull);
    });
  });
}
