import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/widgets/agent_avatar.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/filter_chip_bar.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/contact_repository.dart';
import '../../domain/contact.dart';

/// Which lifecycle segment the Contacts list is filtered to. Null is "All".
final contactStageProvider =
    StateProvider<LifecycleStage?>((Ref ref) => null);

/// Lifecycle stage as a pill, or null when the backend sent nothing we
/// recognise. Blocked outranks the stage — it is the fact that changes what an
/// agent may do next.
({String label, StatusTone tone})? stageBadge(
  AppLocalizations l10n,
  Contact c,
) {
  if (c.isBlocked) {
    return (label: l10n.cdBlocked, tone: StatusTone.danger);
  }
  return switch (c.lifecycleStage) {
    LifecycleStage.customer =>
      (label: l10n.ctStageCustomer, tone: StatusTone.success),
    LifecycleStage.lead => (label: l10n.ctStageLead, tone: StatusTone.info),
    LifecycleStage.vip => (label: l10n.ctStageVip, tone: StatusTone.warning),
    null => null,
  };
}

/// Contacts — Figma 278:2.
class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<Contact>> rows = ref.watch(contactListProvider);
    final LifecycleStage? stage = ref.watch(contactStageProvider);

    return Scaffold(
      appBar: AppHeader.search(
        title: l10n.contactsTitle,
        searchHint: l10n.contactsSearchHint,
        onSearchChanged: (String q) =>
            ref.read(contactSearchProvider.notifier).state = q,
        trailing: const AgentAvatar(),
      ),
      floatingActionButton: FloatingActionButton(
        // Distinct hero tag. Inbox and Contacts are both kept alive by
        // StatefulShellRoute.indexedStack, so two FABs sharing Flutter's
        // default tag collide and throw on every tab switch.
        heroTag: 'fab-contacts',
        onPressed: () => context.push(AppRoutes.contactNew),
        // A plain plus, per the frame. person_add_alt read as a distinct
        // "invite" action next to the list's own rows.
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: <Widget>[
          // Lifecycle segments, per the frame. Filtering happens on the loaded
          // page rather than server-side: the contacts endpoint takes no stage
          // parameter, and quietly refetching on every chip tap would make the
          // segments feel slower than the list they filter.
          FilterChipBar(
            options: <FilterOption>[
              FilterOption(id: '', label: l10n.ctFilterAll),
              FilterOption(
                id: LifecycleStage.customer.name,
                label: l10n.ctStageCustomer,
              ),
              FilterOption(
                id: LifecycleStage.lead.name,
                label: l10n.ctStageLead,
              ),
              FilterOption(id: LifecycleStage.vip.name, label: l10n.ctStageVip),
            ],
            selectedId: stage?.name ?? '',
            onSelected: (String id) => ref
                .read(contactStageProvider.notifier)
                .state = id.isEmpty ? null : LifecycleStage.values.byName(id),
          ),
          Expanded(
            child: AsyncValueView<List<Contact>>(
              value: rows,
              onRetry: () => ref.invalidate(contactListProvider),
              builder: (List<Contact> items) {
                final List<Contact> shown = stage == null
                    ? items
                    : items
                        .where((Contact c) => c.lifecycleStage == stage)
                        .toList();

                if (shown.isEmpty) {
                  return EmptyState(
                    icon: Icons.people_outline,
                    title: l10n.contactsEmptyTitle,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(contactListProvider),
                  child: ListView.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, __) => const Divider(indent: 76),
                    itemBuilder: (BuildContext context, int i) {
                      final Contact c = shown[i];
                      final String display = c.name.isEmpty ? c.phone : c.name;
                      final badge = stageBadge(l10n, c);
                      return AppListTile(
                        title: display,
                        subtitle: c.phone,
                        leading: InitialsAvatar(name: display),
                        // The frame's trailing slot is the lifecycle pill, not
                        // a chevron. Omitted rather than faked when the backend
                        // sent no recognised stage.
                        showChevron: badge == null,
                        trailing: badge == null
                            ? null
                            : StatusPill(
                                label: badge.label,
                                tone: badge.tone,
                              ),
                        onTap: () => context.push(AppRoutes.contact(c.uid)),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
