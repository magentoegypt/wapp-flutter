import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/account/presentation/presence_controller.dart';
import '../features/agents/presentation/screens/agents_screen.dart';
import '../features/automation/data/bot_flow_repository.dart';
import '../features/automation/data/bot_reply_repository.dart';
import '../features/campaigns/data/campaign_repository.dart';
import '../features/campaigns/presentation/screens/campaigns_screen.dart';
import '../features/contacts/data/contact_repository.dart';
import '../features/inbox/data/conversation_repository.dart';
import '../features/reports/data/report_repository.dart';
import '../features/settings/data/messenger_profile_repository.dart';
import '../features/teams/data/team_repository.dart';
import '../features/templates/data/template_repository.dart';

/// Drops everything the signed-out agent could still see.
///
/// Signing out reset `AuthState` and nothing else, so the next agent to sign in
/// on the same device opened Teams or Templates onto the previous agent's
/// workspace — real rows, from an account they were no longer authenticated as,
/// held until something happened to refetch them.
///
/// This lives in `lib/app` rather than in the auth feature on purpose. It has
/// to name providers from a dozen features, and the composition root is already
/// the layer that knows about all of them (see `router.dart`); putting it under
/// `features/auth` would have auth importing every one of its siblings.
///
/// **Only providers that outlive their screen belong here.** Anything declared
/// `.autoDispose` — the inbox, contacts, agents, campaign and dashboard lists,
/// `pendingCallsProvider`, and every derived report provider — is already gone
/// by the time this runs, and listing it would suggest a guarantee this
/// function is not the one making.
void clearSessionScopedState(WidgetRef ref) {
  // Plain FutureProviders. These are the leak: each one holds a decoded list
  // from the previous session for as long as the app is running.
  ref.invalidate(teamListProvider);
  ref.invalidate(templateListProvider);
  ref.invalidate(botFlowListProvider);
  ref.invalidate(botReplyListProvider);
  ref.invalidate(messengerProfileProvider);

  // Per-session UI state. Less serious than the lists above — a stale filter
  // leaks a preference, not data — but an agent inheriting someone else's
  // search text and date windows makes the app look like it did not sign out
  // properly, which after this bug is exactly the impression to avoid.
  ref.invalidate(presenceProvider);
  ref.invalidate(inboxFilterProvider);
  ref.invalidate(contactSearchProvider);
  ref.invalidate(agentSearchProvider);
  ref.invalidate(campaignSearchProvider);
  ref.invalidate(campaignArchivedProvider);
  ref.invalidate(conversationalQueryProvider);
  ref.invalidate(pauseWindowProvider);
  ref.invalidate(qualityWindowProvider);
  ref.invalidate(targetMonthProvider);
}
