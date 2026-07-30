import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../core/widgets/message_composer.dart';
import '../../../../core/widgets/note_card.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/conversation_repository.dart';
import '../../data/note_repository.dart';
import '../../domain/conversation.dart';
import '../../domain/internal_note.dart';

/// Internal notes — Figma 321:6.
///
/// A pushed full page, not a sheet. The privacy banner and the sticky-note
/// palette are both load-bearing: they are what make it obvious at a glance
/// that this content never reaches the customer.
class InternalNotesScreen extends ConsumerWidget {
  const InternalNotesScreen({required this.contactUid, super.key});

  final String contactUid;

  Future<void> _add(WidgetRef ref, String body) async {
    await ref.read(noteRepositoryProvider).add(contactUid, body);
    ref.invalidate(notesProvider(contactUid));
  }

  /// Edits a note in place. The frame puts an edit glyph on every card beside
  /// delete; without it a typo could only be fixed by deleting and retyping,
  /// which also loses the note's original timestamp and author line.
  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    InternalNote note,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextEditingController controller =
        TextEditingController(text: note.body);
    final String? body = await showDialog<String>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(l10n.notesEditTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 3,
          decoration: InputDecoration(hintText: l10n.notesComposerHint),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(controller.text.trim()),
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );
    controller.dispose();

    // Unchanged or emptied — an empty note would read as a deletion the user
    // did not ask for.
    if (body == null || body.isEmpty || body == note.body) return;
    await ref.read(noteRepositoryProvider).update(note.uid, body);
    ref.invalidate(notesProvider(contactUid));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    InternalNote note,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(l10n.actionDelete),
        content: Text(note.body, maxLines: 4, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await ref.read(noteRepositoryProvider).remove(note.uid);
    ref.invalidate(notesProvider(contactUid));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<InternalNote>> notes =
        ref.watch(notesProvider(contactUid));
    final String locale = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      appBar: AppHeader.back(title: l10n.notesTitle),
      body: Column(
        children: <Widget>[
          // Whose notes these are. Without it the screen gave no indication of
          // which contact you were annotating — a real hazard on a shared inbox
          // where an agent arrives here from a sheet two screens deep.
          _ContactBand(
            contactUid: contactUid,
            noteCount: notes.valueOrNull?.length,
          ),
          AppBanner(
            message: l10n.notesPrivacyNotice,
            tone: BannerTone.brand,
            icon: Icons.lock_outline,
          ),
          Expanded(
            child: AsyncValueView<List<InternalNote>>(
              value: notes,
              onRetry: () => ref.invalidate(notesProvider(contactUid)),
              builder: (List<InternalNote> items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.sticky_note_2_outlined,
                    title: l10n.notesEmptyTitle,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(AppDimens.gutter),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int i) {
                    final InternalNote n = items[i];
                    return NoteCard(
                      author: n.authorName,
                      timeLabel: n.createdAt == null
                          ? ''
                          : DateFormat.yMMMd(locale).add_jm().format(n.createdAt!),
                      body: n.body,
                      edited: n.edited,
                      onEdit: () => _edit(context, ref, n),
                      onDelete: () => _confirmDelete(context, ref, n),
                    );
                  },
                );
              },
            ),
          ),
          MessageComposer(
            hintText: l10n.notesComposerHint,
            sendLabel: l10n.notesAdd,
            onSend: (String body) => _add(ref, body),
          ),
        ],
      ),
    );
  }
}

/// Contact identity band under the app bar, with a note count.
///
/// Reads the chat thread for the name and phone rather than taking them as
/// parameters: the notes route is reachable from the chat actions sheet and
/// from conversation info, and threading two strings through both call sites
/// would let them drift out of sync with the thread the user is actually in.
class _ContactBand extends ConsumerWidget {
  const _ContactBand({required this.contactUid, this.noteCount});

  final String contactUid;
  final int? noteCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ChatThread? t = ref.watch(chatThreadProvider(contactUid)).valueOrNull;
    if (t == null) return const SizedBox.shrink();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(AppDimens.gutter),
      child: Row(
        children: <Widget>[
          InitialsAvatar(name: t.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (t.phone != null)
                  Text(
                    t.phone!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
              ],
            ),
          ),
          if (noteCount != null) ...<Widget>[
            const SizedBox(width: 8),
            // The note palette, not a semantic tone — the count describes this
            // screen's own content rather than any state of the conversation.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColor.noteFill,
                border: Border.all(color: AppColor.noteLine),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                l10n.notesCount(noteCount!),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColor.noteInk,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
