import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/presentation/screens/more_screen.dart';
import '../features/agents/presentation/screens/agent_detail_screen.dart';
import '../features/agents/presentation/screens/agents_screen.dart';
import '../features/campaigns/presentation/screens/campaign_detail_screen.dart';
import '../features/campaigns/presentation/screens/campaigns_screen.dart';
import '../features/campaigns/presentation/screens/create_campaign_screen.dart';
import '../features/inbox/presentation/screens/conversation_info_screen.dart';
import '../features/quick_replies/presentation/screens/quick_replies_screen.dart';
import '../features/quick_replies/presentation/screens/quick_reply_editor_screen.dart';
import '../features/search/presentation/screens/search_screen.dart';
import '../features/account/presentation/screens/profile_screen.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/contacts/presentation/screens/add_contact_screen.dart';
import '../features/contacts/presentation/screens/contact_detail_screen.dart';
import '../features/contacts/presentation/screens/contacts_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../features/dev/presentation/component_gallery_screen.dart';
import '../features/inbox/presentation/screens/chat_screen.dart';
import '../features/inbox/presentation/screens/inbox_screen.dart';
import '../features/inbox/presentation/screens/internal_notes_screen.dart';
import 'routes.dart';
import 'shell/app_shell.dart';

final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

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
      final bool onLogin = location == AppRoutes.login;

      switch (status) {
        // Still validating a stored token. Hold on the splash so the sign-in
        // form never flashes for an already-authenticated user.
        case AuthStatus.unknown:
          return onSplash ? null : AppRoutes.splash;

        case AuthStatus.signedOut:
          return onLogin ? null : AppRoutes.login;

        // Signed in. Leave splash and login behind; everything else is a
        // legitimate destination, including a deep link.
        case AuthStatus.signedIn:
          return (onSplash || onLogin) ? AppRoutes.home : null;
      }
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
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
        ],
      ),

      GoRoute(
        path: AppRoutes.contactNew,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const AddContactScreen(),
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

      GoRoute(
        path: AppRoutes.devGallery,
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const ComponentGalleryScreen(),
      ),
    ],
  );
});
