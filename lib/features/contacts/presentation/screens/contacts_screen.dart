import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/widgets/agent_avatar.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/channel_badge.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/contact_repository.dart';
import '../../domain/contact.dart';

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
          // No lifecycle segment row. The frame has one, but nothing feeds it:
          // contacts.status is an integer column carrying blocked/active, never
          // a customer/lead/vip vocabulary, so every segment matched zero
          // contacts on device. Three chips that always return "no contacts" are
          // worse than no chips. LifecycleStage stays in the domain, mapped
          // defensively, ready for the day the API sends one.
          Expanded(
            child: AsyncValueView<List<Contact>>(
              value: rows,
              onRetry: () => ref.invalidate(contactListProvider),
              builder: (List<Contact> items) {
                final List<Contact> shown = items;

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
                      // stageBadge is non-null only for a blocked contact
                      // today, so the chevron is what almost every row gets.
                      final badge = stageBadge(l10n, c);
                      return AppListTile(
                        title: display,
                        // Not c.phone. On an Instagram contact `waId` holds the
                        // IGSID — a 16-digit account id that reads as a broken
                        // phone number beside real ones. subtitleLine gives the
                        // @username there and the number everywhere else.
                        subtitle: c.subtitleLine,
                        // Same badge as the inbox rows, for the same reason:
                        // the reply rules differ by channel and an agent needs
                        // to know which before opening the thread.
                        leading: AvatarWithChannel(
                          name: display,
                          channel: c.channel,
                        ),
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
