import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/message_composer.dart';
import '../../../../core/widgets/note_card.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/note_repository.dart';
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
