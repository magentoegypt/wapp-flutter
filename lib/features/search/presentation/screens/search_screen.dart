import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/filter_chip_bar.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../campaigns/data/campaign_repository.dart';
// campaignBadge lives next to the campaigns list so the two can never disagree
// on which tone a lifecycle state gets; reusing it beats a second mapping here.
import '../../../campaigns/presentation/screens/campaigns_screen.dart'
    show campaignBadge;
import '../../../contacts/domain/contact.dart';
import '../../../inbox/domain/conversation.dart';
import '../../data/search_providers.dart';
import '../../domain/search_result.dart';

/// Search — Figma 281:2.
class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String query = ref.watch(searchQueryProvider).trim();
    final SearchScope scope = ref.watch(searchScopeProvider);
    final AsyncValue<List<SearchResult>> results =
        ref.watch(searchResultsProvider);
    final String agent =
        ref.watch(authControllerProvider).session?.user.name ?? '';

    return Scaffold(
      appBar: AppHeader.search(
        title: l10n.searchTitle,
        searchHint: l10n.inboxSearchHint,
        // Pushed route - without this there is no way back out.
        showBack: true,
        trailing:
            agent.isEmpty ? null : InitialsAvatar.onBrand(name: agent, size: 36),
        onSearchChanged: (String q) =>
            ref.read(searchQueryProvider.notifier).state = q,
      ),
      body: Column(
        children: <Widget>[
          // Always mounted, including before the query is long enough: the row
          // appearing on the second keystroke would shove the first results
          // down the screen just as they land.
          FilterChipBar(
            options: <FilterOption>[
              FilterOption(id: SearchScope.all.name, label: l10n.inboxFilterAll),
              FilterOption(id: SearchScope.chats.name, label: l10n.navChats),
              FilterOption(
                id: SearchScope.contacts.name,
                label: l10n.contactsTitle,
              ),
              FilterOption(
                id: SearchScope.campaigns.name,
                label: l10n.moreCampaigns,
              ),
            ],
            selectedId: scope.name,
            onSelected: (String id) => ref
                .read(searchScopeProvider.notifier)
                .state = SearchScope.values.byName(id),
          ),
          Expanded(
            child: query.length < 2
                ? EmptyState(
                    icon: Icons.search,
                    title: l10n.searchPrompt,
                    message: l10n.searchMinChars,
                  )
                : AsyncValueView<List<SearchResult>>(
                    value: results,
                    onRetry: () => ref.invalidate(searchResultsProvider),
                    builder: (List<SearchResult> items) {
                      if (items.isEmpty) {
                        return EmptyState(
                          icon: Icons.search_off,
                          title: l10n.searchNoMatches,
                          message: l10n.searchNothingFor(query),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          SectionLabel(l10n.searchResultsCount(items.length)),
                          Expanded(
                            child: ListView.separated(
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(indent: 76),
                              itemBuilder: (BuildContext context, int i) =>
                                  _ResultRow(result: items[i]),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// One merged result. Each slice keeps the leading, trailing and tap target of
/// its own list screen, so a row found through search looks and behaves exactly
/// like the same row found by browsing.
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    return switch (result) {
      ChatResult(conversation: final Conversation c) => _chat(context, c),
      ContactResult(contact: final Contact c) => _contact(context, c),
      CampaignResult(campaign: final Campaign c) => _campaign(context, c),
    };
  }

  Widget _chat(BuildContext context, Conversation c) {
    return AppListTile(
      title: c.name,
      subtitle: c.lastMessage,
      leading: InitialsAvatar(name: c.name),
      showChevron: false,
      trailing: Text(
        _stamp(context, c.lastMessageAt),
        style: Theme.of(context).textTheme.labelMedium,
      ),
      onTap: () => context.push(AppRoutes.chat(c.contactUid)),
    );
  }

  Widget _contact(BuildContext context, Contact c) {
    // An imported contact can arrive without a name; the phone is then the only
    // thing to identify it by, in the title and in the initials both.
    final String label = c.name.isEmpty ? c.phone : c.name;

    return AppListTile(
      title: label,
      subtitle: c.phone,
      leading: InitialsAvatar(name: label),
      onTap: () => context.push(AppRoutes.contact(c.uid)),
    );
  }

  Widget _campaign(BuildContext context, Campaign c) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String locale = Localizations.localeOf(context).toLanguageTag();
    final ({String label, StatusTone tone}) badge = campaignBadge(l10n, c.status);

    return AppListTile(
      title: c.title,
      subtitle: c.scheduledAt == null
          ? l10n.campContacts(c.totalContacts)
          : '${l10n.campContacts(c.totalContacts)} · '
              '${DateFormat.yMMMd(locale).format(c.scheduledAt!)}',
      leading: const IconTile(
        icon: Icons.campaign_outlined,
        color: AppColor.warning,
      ),
      trailing: StatusPill(label: badge.label, tone: badge.tone),
      onTap: () => context.push(AppRoutes.campaign(c.uid)),
    );
  }
}

/// Time for today, weekday within the last week, otherwise a short date.
/// Formatting goes through [DateFormat] with the ambient locale so Arabic gets
/// Arabic weekday names and numerals.
///
/// This is the inbox row's helper, duplicated rather than shared: its real home
/// is a formatter under `lib/core/util`, and until it moves there the two copies
/// have to be kept in step.
String _stamp(BuildContext context, DateTime? at) {
  if (at == null) return '';
  final String locale = Localizations.localeOf(context).toLanguageTag();
  final DateTime now = DateTime.now();
  final Duration age = now.difference(at);

  if (age.inDays == 0 && now.day == at.day) {
    return DateFormat.Hm(locale).format(at);
  }
  if (age.inDays < 7) return DateFormat.E(locale).format(at);
  return DateFormat.yMd(locale).format(at);
}
