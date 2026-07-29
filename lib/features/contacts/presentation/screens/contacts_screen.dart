import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/contact_repository.dart';
import '../../domain/contact.dart';

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
      ),
      floatingActionButton: FloatingActionButton(
        // Distinct hero tag. Inbox and Contacts are both kept alive by
        // StatefulShellRoute.indexedStack, so two FABs sharing Flutter's
        // default tag collide and throw on every tab switch.
        heroTag: 'fab-contacts',
        onPressed: () => context.push(AppRoutes.contactNew),
        child: const Icon(Icons.person_add_alt),
      ),
      body: AsyncValueView<List<Contact>>(
        value: rows,
        onRetry: () => ref.invalidate(contactListProvider),
        builder: (List<Contact> items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.people_outline,
              title: l10n.contactsEmptyTitle,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(contactListProvider),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(indent: 76),
              itemBuilder: (BuildContext context, int i) {
                final Contact c = items[i];
                return AppListTile(
                  title: c.name.isEmpty ? c.phone : c.name,
                  subtitle: c.phone,
                  leading: InitialsAvatar(name: c.name.isEmpty ? c.phone : c.name),
                  onTap: () => context.push(AppRoutes.contact(c.uid)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
