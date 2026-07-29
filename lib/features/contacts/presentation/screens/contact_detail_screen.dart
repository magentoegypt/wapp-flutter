import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../data/contact_repository.dart';
import '../../domain/contact.dart';
import '../../../../l10n/app_localizations.dart';

/// Contact detail — Figma 290:68.
class ContactDetailScreen extends ConsumerWidget {
  const ContactDetailScreen({required this.uid, super.key});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<Contact> contact = ref.watch(contactDetailProvider(uid));

    return Scaffold(
      appBar: AppHeader.back(title: contact.valueOrNull?.name ?? ''),
      body: AsyncValueView<Contact>(
        value: contact,
        onRetry: () => ref.invalidate(contactDetailProvider(uid)),
        builder: (Contact c) => ListView(
          children: <Widget>[
            const SizedBox(height: 20),
            Center(
              child: InitialsAvatar(
                name: c.name.isEmpty ? c.phone : c.name,
                size: AppDimens.avatarHero,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                c.name.isEmpty ? c.phone : c.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                c.phone,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (c.isBlocked) ...<Widget>[
              const SizedBox(height: 8),
              Center(
                child: StatusPill(label: l10n.cdBlocked, tone: StatusTone.danger),
              ),
            ],

            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppDimens.gutter),
              child: FilledButton.icon(
                onPressed: () => context.push(AppRoutes.chat(c.uid)),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: Text(l10n.cdOpenConversation),
              ),
            ),

            SectionLabel(l10n.cdDetails),
            AppListTile(
              title: l10n.cdPhone,
              subtitle: c.phone,
              leading: const IconTile(
                icon: Icons.phone_outlined,
                color: AppColor.success,
              ),
              showChevron: false,
            ),
            if (c.email != null && c.email!.isNotEmpty)
              AppListTile(
                title: l10n.cdEmail,
                subtitle: c.email,
                leading: const IconTile(
                  icon: Icons.mail_outline,
                  color: AppColor.info,
                ),
                showChevron: false,
              ),

            if (c.labels.isNotEmpty) ...<Widget>[
              SectionLabel(l10n.cdLabels),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.gutter,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final String label in c.labels)
                      StatusPill(
                        label: label,
                        tone: StatusTone.info,
                        showDot: false,
                      ),
                  ],
                ),
              ),
            ],

            if (c.groups.isNotEmpty) ...<Widget>[
              SectionLabel(l10n.cdGroups),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.gutter,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final String g in c.groups)
                      StatusPill(
                        label: g,
                        tone: StatusTone.neutral,
                        showDot: false,
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}
