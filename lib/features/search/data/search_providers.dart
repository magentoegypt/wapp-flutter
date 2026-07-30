import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../campaigns/data/campaign_repository.dart';
import '../../contacts/data/contact_repository.dart';
import '../../contacts/domain/contact.dart';
import '../../inbox/data/conversation_repository.dart';
import '../../inbox/domain/conversation.dart';
import '../domain/search_result.dart';

/// The live query. Kept at module scope so the field and the results provider
/// stay in sync without threading a controller through.
final searchQueryProvider = StateProvider.autoDispose<String>((Ref ref) => '');

/// The selected scope chip. Auto-disposed with the query so leaving and
/// re-entering search always starts on All rather than on whatever the previous
/// visit narrowed to.
final searchScopeProvider =
    StateProvider.autoDispose<SearchScope>((Ref ref) => SearchScope.all);

/// Results for the current query, merged across the scopes it covers.
///
/// There is no `/search` endpoint — the backend exposes one query parameter per
/// domain — so this fans out to the three repositories that already own those
/// calls instead of adding a fourth. The requests are issued together: running
/// them in sequence would make the All scope three round-trips deep.
final searchResultsProvider =
    FutureProvider.autoDispose<List<SearchResult>>((Ref ref) async {
  final String q = ref.watch(searchQueryProvider).trim();
  // Don't hit the API on a single character — it returns most of the workspace.
  if (q.length < 2) return const <SearchResult>[];

  final SearchScope scope = ref.watch(searchScopeProvider);
  // Every dependency is read before the first await. A `ref.watch` after one
  // runs against a provider this one may already have been disposed by.
  final ConversationRepository conversations =
      ref.watch(conversationRepositoryProvider);
  final ContactRepository contacts = ref.watch(contactRepositoryProvider);
  final CampaignRepository campaigns = ref.watch(campaignRepositoryProvider);

  final List<Future<List<SearchResult>>> slices = <Future<List<SearchResult>>>[
    if (scope.covers(SearchScope.chats))
      conversations.list(query: q).then(
            (List<Conversation> rows) =>
                rows.map<SearchResult>(ChatResult.new).toList(),
          ),
    if (scope.covers(SearchScope.contacts))
      contacts.list(query: q).then(
            (List<Contact> rows) =>
                rows.map<SearchResult>(ContactResult.new).toList(),
          ),
    if (scope.covers(SearchScope.campaigns))
      campaigns.list().then(
            (List<Campaign> rows) => rows
                .where((Campaign c) => _matches(c.title, q))
                .map<SearchResult>(CampaignResult.new)
                .toList(),
          ),
  ];

  final List<List<SearchResult>> loaded = await Future.wait(slices);
  // Chips read chats → contacts → campaigns; the merged list keeps that order
  // so narrowing the scope only ever removes rows, never reshuffles them.
  return loaded.expand((List<SearchResult> slice) => slice).toList();
});

/// `/campaigns` takes no query parameter, so the campaign slice is narrowed on
/// the client. Title only — it is the one field of the list payload a user
/// would search by, and matching on the status label would return every draft
/// for the query "draft".
bool _matches(String value, String query) =>
    value.toLowerCase().contains(query.toLowerCase());
