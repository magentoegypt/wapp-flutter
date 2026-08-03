import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/presentation/screens/more_screen.dart';
import '../features/agents/presentation/screens/agent_detail_screen.dart';
import '../features/agents/presentation/screens/agents_screen.dart';
import '../features/automation/presentation/screens/bot_flow_editor_screen.dart';
import '../features/automation/presentation/screens/bot_flows_screen.dart';
import '../features/reports/presentation/screens/agent_targets_screen.dart';
import '../features/reports/presentation/screens/conversational_report_screen.dart';
import '../features/reports/presentation/screens/pause_reasons_screen.dart';
import '../features/reports/presentation/screens/quality_reviews_screen.dart';
import '../features/reports/presentation/screens/reports_screen.dart';
import '../features/automation/presentation/screens/bot_replies_screen.dart';
import '../features/automation/presentation/screens/bot_reply_editor_screen.dart';
import '../features/campaigns/presentation/screens/campaign_detail_screen.dart';
import '../features/campaigns/presentation/screens/campaigns_screen.dart';
import '../features/campaigns/presentation/screens/create_campaign_screen.dart';
import '../features/calls/presentation/screens/active_call_screen.dart';
import '../features/calls/presentation/screens/call_ended_screen.dart';
import '../features/calls/presentation/screens/incoming_call_screen.dart';
import '../features/calls/presentation/screens/outgoing_call_screen.dart';
import '../features/conversation_actions/presentation/screens/assign_screen.dart';
import '../features/conversation_actions/presentation/screens/call_history_screen.dart';
import '../features/conversation_actions/presentation/screens/call_permission_screen.dart';
import '../features/conversation_actions/presentation/screens/clear_history_screen.dart';
import '../features/conversation_actions/presentation/screens/history_access_screen.dart';
import '../features/conversation_actions/presentation/screens/manage_labels_screen.dart';
import '../features/conversation_actions/presentation/screens/quality_review_screen.dart';
import '../features/conversation_actions/presentation/screens/reminder_screen.dart';
import '../features/conversation_actions/presentation/screens/send_template_screen.dart';
import '../features/conversation_actions/presentation/screens/snooze_screen.dart';
import '../features/conversation_actions/presentation/screens/transfer_screen.dart';
import '../features/inbox/presentation/screens/conversation_info_screen.dart';
import '../features/quick_replies/presentation/screens/quick_replies_screen.dart';
import '../features/quick_replies/presentation/screens/quick_reply_editor_screen.dart';
import '../features/search/presentation/screens/search_screen.dart';
import '../features/account/presentation/screens/profile_screen.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/contacts/presentation/screens/contact_form_screen.dart';
import '../features/contacts/presentation/screens/contact_detail_screen.dart';
import '../features/contacts/presentation/screens/contacts_screen.dart';
import '../features/auth/presentation/screens/forgot_password_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/reset_password_screen.dart';
import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../features/dev/presentation/component_gallery_screen.dart';
import '../features/inbox/presentation/screens/chat_screen.dart';
import '../features/inbox/presentation/screens/inbox_screen.dart';
import '../features/inbox/presentation/screens/instagram_send_screen.dart';
import '../features/inbox/presentation/screens/internal_notes_screen.dart';
import '../features/settings/presentation/screens/instagram_settings_screen.dart';
import '../features/templates/presentation/screens/template_editor_screen.dart';
import '../features/templates/presentation/screens/templates_screen.dart';
import '../features/teams/presentation/screens/team_editor_screen.dart';
import '../features/teams/presentation/screens/teams_screen.dart';
import 'routes.dart';
import 'shell/app_shell.dart';

final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// Where the user was headed before the session finished resolving.
///
/// A cold start with a deep link - a push notification, a shared chat URL -
/// arrives while auth is still `unknown`, so the redirect parks on the splash.
/// Without remembering the destination the user is silently dropped on Home
/// once auth lands, and the link is lost.
String? _pendingDestination;

// Auth changes are pushed into the router from ClickalizeApp, which calls
// GoRouter.refresh() from a widget-level ref.listen. That was previously done
// with a ChangeNotifier built inside this provider; the subscription did not
// reliably fire, leaving the app parked on the sign-in screen after a cold
// start even though the session had restored. A widget-level listen is the
// supported place for side effects and does fire.

/// App router.
///
/// Route placement encodes the `Shell` column of the handoff's screen
/// inventory, and that mapping is load-bearing:
///
/// * `tabs`  → declared inside a [StatefulShellBranch]; the bottom bar stays.
/// * `push`  → declared at top level with `parentNavigatorKey: _rootKey`, so
///             the pushed page covers the bar.
/// * `modal` → not a route at all; Chat actions opens as a bottom sheet.
/// * `none`  → Login, outside the shell.
///
/// Literal segments are declared before parameterized siblings so `/contacts/new`
/// is not swallowed by `/contacts/:uid`.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: true,
    redirect: (BuildContext context, GoRouterState state) {
      final AuthStatus status = ref.read(authControllerProvider).status;
      final String location = state.matchedLocation;

      // The component gallery is a development surface and stays reachable
      // without a session.
      if (location.startsWith('/dev/')) return null;

      final bool onSplash = location == AppRoutes.splash;
      // Password recovery is part of the signed-out surface: the redirect must
      // let these through or it bounces straight back to Login.
      final bool onLogin = location == AppRoutes.login ||
          location == AppRoutes.forgotPassword ||
          location == AppRoutes.resetPassword;

      switch (status) {
        // Still validating a stored token. Hold on the splash so the sign-in
        // form never flashes for an already-authenticated user, but remember
        // where they were going.
        case AuthStatus.unknown:
          if (!onSplash && !onLogin) {
            _pendingDestination = state.uri.toString();
          }
          return onSplash ? null : AppRoutes.splash;

        case AuthStatus.signedOut:
          return onLogin ? null : AppRoutes.login;

        // Signed in. Leave splash and login behind, honouring a deep link
        // captured before the session resolved; everything else is already a
        // legitimate destination.
        case AuthStatus.signedIn:
          if (onSplash || onLogin) {
            final String? pending = _pendingDestination;
            _pendingDestination = null;
            return pending ?? AppRoutes.home;
          }
          return null;
      }
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (_, GoRouterState state) =>
            ResetPasswordScreen(email: state.extra as String?),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),

      // ---- Persistent tab shell -------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (_, __, StatefulNavigationShell shell) =>
            AppShell(navigationShell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.home,
                builder: (_, __) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.chats,
                builder: (_, __) => const InboxScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.contacts,
                builder: (_, __) => const ContactsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.more,
                builder: (_, __) => const MoreScreen(),
                routes: <RouteBase>[
                  // Nested, so Profile keeps the bottom bar — the inventory
                  // marks it `tabs`, unlike its sibling More destinations.
                  GoRoute(
                    path: 'profile',
                    builder: (_, __) => const ProfileScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // ---- Pushed over the shell ------------------------------------------
      GoRoute(
        path: AppRoutes.search,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const SearchScreen(),
      ),
      GoRoute(
        path: '/chats/:uid',
        parentNavigatorKey: _rootKey,
        builder: (_, GoRouterState s) =>
            ChatScreen(contactUid: s.pathParameters['uid']!),
        routes: <RouteBase>[
          GoRoute(
            path: 'info',
            parentNavigatorKey: _rootKey,
            builder: (_, GoRouterState s) =>
                ConversationInfoScreen(contactUid: s.pathParameters['uid']!),
          ),
          GoRoute(
            path: 'notes',
            parentNavigatorKey: _rootKey,
            builder: (_, GoRouterState s) =>
                InternalNotesScreen(contactUid: s.pathParameters['uid']!),
          ),

          // Conversation actions. Every one is a pushed route over the shell —
          // the ⋮ sheet is the launcher, not a destination, so it stays a
          // bottom sheet and these are where its rows actually go.
          GoRoute(
            path: 'snooze',
            parentNavigatorKey: _rootKey,
            builder: (_, GoRouterState s) =>
                SnoozeScreen(contactUid: s.pathParameters['uid']!),
          ),
          GoRoute(
            path: 'transfer',
            parentNavigatorKey: _rootKey,
            builder: (_, GoRouterState s) =>
                TransferScreen(contactUid: s.pathParameters['uid']!),
          ),
          GoRoute(
            path: 'assign',
            parentNavigatorKey: _rootKey,
            builder: (_, GoRouterState s) =>
                AssignScreen(contactUid: s.pathParameters['uid']!),
          ),
          GoRoute(
            path: 'review',
            parentNavigatorKey: _rootKey,
            builder: (_, GoRouterState s) =>
                QualityReviewScreen(contactUid: s.pathParameters['uid']!),
          ),
          GoRoute(
            path: 'labels',
            parentNavigatorKey: _rootKey,
            builder: (_, GoRouterState s) => ManageLabelsScreen(
              contactUid: s.pathParameters['uid']!,
              // Already-applied labels come through as `extra` so the screen can
              // pre-tick them; setLabels REPLACES the set, so opening it without
              // them and saving would silently clear every label the
              // conversation had.
              initial: (s.extra as List<String>?) ?? const <String>[],
            ),
          ),
          GoRoute(
            path: 'template',
            parentNavigatorKey: _rootKey,
            builder: (_, GoRouterState s) =>
                SendTemplateScreen(contactUid: s.pathParameters['uid']!),
          ),
          GoRoute(
            path: 'calls',
            parentNavigatorKey: _rootKey,
            builder: (_, GoRouterState s) =>
                CallHistoryScreen(contactUid: s.pathParameters['uid']!),
          ),
          GoRoute(
            path: 'call-permission',
            parentNavigatorKey: _rootKey,
            builder: (_, GoRouterState s) =>
                CallPermissionScreen(contactUid: s.pathParameters['uid']!),
          ),
          GoRoute(
            path: 'history-access',
            parentNavigatorKey: _rootKey,
            builder: (_, GoRouterState s) =>
                HistoryAccessScreen(contactUid: s.pathParameters['uid']!),
          ),
          GoRoute(
            path: 'reminder',
            parentNavigatorKey: _rootKey,
            builder: (_, GoRouterState s) =>
                ReminderScreen(contactUid: s.pathParameters['uid']!),
          ),
          GoRoute(
            path: 'clear-history',
            parentNavigatorKey: _rootKey,
            builder: (_, GoRouterState s) =>
                ClearHistoryScreen(contactUid: s.pathParameters['uid']!),
          ),
          GoRoute(
            path: 'instagram',
            parentNavigatorKey: _rootKey,
            builder: (_, GoRouterState s) =>
                InstagramSendScreen(contactUid: s.pathParameters['uid']!),
          ),
        ],
      ),

      // Calling. Full-screen and outside the shell entirely — a ringing phone
      // is not a tab, and the bottom bar under an active call would invite
      // navigating away from it.
      GoRoute(
        path: '/calls/:uid/incoming',
        parentNavigatorKey: _rootKey,
        builder: (_, GoRouterState s) => IncomingCallScreen(
          contactUid: s.pathParameters['uid']!,
          name: s.extra as String?,
        ),
      ),
      GoRoute(
        path: '/calls/:uid/outgoing',
        parentNavigatorKey: _rootKey,
        builder: (_, GoRouterState s) => OutgoingCallScreen(
          contactUid: s.pathParameters['uid']!,
          name: s.extra as String?,
        ),
      ),
      GoRoute(
        path: '/calls/:uid/active',
        parentNavigatorKey: _rootKey,
        builder: (_, GoRouterState s) => ActiveCallScreen(
          contactUid: s.pathParameters['uid']!,
          name: s.extra as String?,
        ),
      ),
      GoRoute(
        path: '/calls/:uid/ended',
        parentNavigatorKey: _rootKey,
        builder: (_, GoRouterState s) => CallEndedScreen(
          contactUid: s.pathParameters['uid']!,
          name: s.extra as String?,
        ),
      ),

      GoRoute(
        path: AppRoutes.contactNew,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const ContactFormScreen(),
      ),
      // Declared before `/contacts/:uid` so the literal `edit` segment is not
      // matched as a contact uid.
      GoRoute(
        path: '/contacts/:uid/edit',
        parentNavigatorKey: _rootKey,
        builder: (_, GoRouterState s) =>
            ContactFormScreen(uid: s.pathParameters['uid']!),
      ),
      GoRoute(
        path: '/contacts/:uid',
        parentNavigatorKey: _rootKey,
        builder: (_, GoRouterState s) =>
            ContactDetailScreen(uid: s.pathParameters['uid']!),
      ),

      GoRoute(
        path: AppRoutes.quickReplies,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const QuickRepliesScreen(),
      ),
      GoRoute(
        path: AppRoutes.quickReplyNew,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const QuickReplyEditorScreen(),
      ),
      GoRoute(
        path: '/quick-replies/:uid',
        parentNavigatorKey: _rootKey,
        builder: (_, GoRouterState s) =>
            QuickReplyEditorScreen(uid: s.pathParameters['uid']),
      ),

      GoRoute(
        path: AppRoutes.campaigns,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const CampaignsScreen(),
      ),
      GoRoute(
        path: AppRoutes.campaignNew,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const CreateCampaignScreen(),
      ),
      GoRoute(
        path: '/campaigns/:uid',
        parentNavigatorKey: _rootKey,
        builder: (_, GoRouterState s) =>
            CampaignDetailScreen(uid: s.pathParameters['uid']!),
      ),

      GoRoute(
        path: AppRoutes.agents,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const AgentsScreen(),
      ),
      GoRoute(
        path: '/agents/:uid',
        parentNavigatorKey: _rootKey,
        builder: (_, GoRouterState s) =>
            AgentDetailScreen(uid: s.pathParameters['uid']!),
      ),

      // Literal before parameterised, or '/templates/new' matches ':uid'.
      GoRoute(
        path: AppRoutes.templates,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const TemplatesScreen(),
      ),
      GoRoute(
        path: AppRoutes.templateNew,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const TemplateEditorScreen(),
      ),
      GoRoute(
        path: '/templates/:uid',
        parentNavigatorKey: _rootKey,
        builder: (_, GoRouterState s) =>
            TemplateEditorScreen(uid: s.pathParameters['uid']!),
      ),

      GoRoute(
        path: AppRoutes.teams,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const TeamsScreen(),
      ),
      GoRoute(
        path: AppRoutes.teamNew,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const TeamEditorScreen(),
      ),
      GoRoute(
        path: '/teams/:uid',
        parentNavigatorKey: _rootKey,
        builder: (_, GoRouterState s) =>
            TeamEditorScreen(uid: s.pathParameters['uid']!),
      ),

      GoRoute(
        path: AppRoutes.botReplies,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const BotRepliesScreen(),
      ),
      GoRoute(
        path: AppRoutes.botReplyNew,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const BotReplyEditorScreen(),
      ),
      GoRoute(
        path: '/bot-replies/:uid',
        parentNavigatorKey: _rootKey,
        builder: (_, GoRouterState s) =>
            BotReplyEditorScreen(uid: s.pathParameters['uid']!),
      ),

      GoRoute(
        path: AppRoutes.botFlows,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const BotFlowsScreen(),
      ),
      GoRoute(
        path: AppRoutes.botFlowNew,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const BotFlowEditorScreen(),
      ),
      GoRoute(
        path: '/bot-flows/:uid',
        parentNavigatorKey: _rootKey,
        builder: (_, GoRouterState s) =>
            BotFlowEditorScreen(uid: s.pathParameters['uid']!),
      ),

      // Reporting. Declared before the parameterised routes above would ever
      // see them because each path is literal, so no ordering trap here — but
      // they stay grouped for the same reason the hub exists.
      GoRoute(
        path: AppRoutes.reports,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const ReportsScreen(),
      ),
      GoRoute(
        path: AppRoutes.reportConversational,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const ConversationalReportScreen(),
      ),
      GoRoute(
        path: AppRoutes.reportPauseReasons,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const PauseReasonsScreen(),
      ),
      GoRoute(
        path: AppRoutes.reportQuality,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const QualityReviewsScreen(),
      ),
      GoRoute(
        path: AppRoutes.reportTargets,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const AgentTargetsScreen(),
      ),

      // Workspace settings, so it sits beside /agents rather than under
      // /chats/:uid — nothing here is scoped to a conversation.
      GoRoute(
        path: AppRoutes.instagramSettings,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const InstagramSettingsScreen(),
      ),

      GoRoute(
        path: AppRoutes.devGallery,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const ComponentGalleryScreen(),
      ),
    ],
  );
});
