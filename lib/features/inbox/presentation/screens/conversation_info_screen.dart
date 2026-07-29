import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/conversation_repository.dart';
import '../../data/note_repository.dart';
import '../../domain/conversation.dart';

/// Conversation info — Figma 290:4.
///
/// The contact-side companion to the chat: who they are, who owns the
/// conversation, and the entry point into internal notes.
class ConversationInfoScreen extends ConsumerWidget {
  const ConversationInfoScreen({required this.contactUid, super.key});

  final String contactUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ChatThread> thread =
        ref.watch(chatThreadProvider(contactUid));
    final int noteCount =
        ref.watch(notesProvider(contactUid)).valueOrNull?.length ?? 0;
    final String locale = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      appBar: AppHeader.back(title: l10n.ciTitle),
      body: AsyncValueView<ChatThread>(
        value: thread,
        onRetry: () => ref.invalidate(chatThreadProvider(contactUid)),
        builder: (ChatThread t) => ListView(
          children: <Widget>[
            const SizedBox(height: 20),
            Center(
              child: InitialsAvatar(name: t.name, size: AppDimens.avatarHero),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                t.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (t.phone != null) ...<Widget>[
              const SizedBox(height: 4),
              Center(
                child: Text(
                  t.phone!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],

            SectionLabel(l10n.ciServiceWindow),
            AppListTile(
              title: t.windowOpen ? l10n.ciOpen : l10n.ciClosed,
              subtitle: t.windowExpiresAt == null
                  ? (t.windowOpen ? null : l10n.ciReopenHint)
                  : DateFormat.yMMMd(locale).add_jm().format(t.windowExpiresAt!),
              leading: IconTile(
                icon: Icons.schedule_outlined,
                color: t.windowOpen ? AppColor.success : AppColor.warning,
              ),
              showChevron: false,
              trailing: StatusPill(
                label: t.windowOpen ? l10n.ciOpen : l10n.ciClosed,
                tone: t.windowOpen ? StatusTone.success : StatusTone.warning,
              ),
            ),

            SectionLabel(l10n.ciAssignment),
            AppListTile(
              title: l10n.ciAssignedTo,
              subtitle: t.assignedAgentName ?? l10n.ciUnassigned,
              leading: const IconTile(
                icon: Icons.person_outline,
                color: AppColor.info,
              ),
              showChevron: false,
            ),
            AppListTile(
              title: l10n.ciReplyLock,
              subtitle: t.isReplyLockOpen
                  ? l10n.ciReplyLockFree
                  : l10n.ciReplyLockHeld(t.replyLockHeldBy ?? ''),
              leading: IconTile(
                icon: t.isReplyLockOpen ? Icons.lock_open_outlined : Icons.lock_outline,
                color: t.isReplyLockOpen ? AppColor.inkMuted : AppColor.warning,
              ),
              showChevron: false,
            ),

            SectionLabel(l10n.notesTitle),
            AppListTile(
              title: l10n.notesTitle,
              subtitle: l10n.notesCount(noteCount),
              leading: const IconTile(
                icon: Icons.sticky_note_2_outlined,
                color: AppColor.warning,
              ),
              onTap: () => context.push(AppRoutes.chatNotes(contactUid)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
