import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../contacts/data/contact_repository.dart';
import '../../../contacts/domain/contact.dart';
import '../../../conversation_actions/data/conversation_action_repository.dart';
import '../../../conversation_actions/domain/action_models.dart';
import '../../data/note_repository.dart';
import '../../domain/channel.dart';

/// Chat actions — Figma 330:15.
///
/// The only modal surface in the inventory. Everything else that looks like it
/// might be a sheet (internal notes in particular) is a pushed full page.
///
/// Three things the frame does that a flat list of rows did not:
///
/// * **Four quick actions across the top.** Favourite, Call, Status and Assign
///   are the ones reached mid-conversation, and burying them among twelve
///   equal rows made the common case as expensive as the rare one.
/// * **Four named groups.** Twelve undifferentiated rows is a wall; the groups
///   are how you find the one you came for.
/// * **Counts on the rows that have them.** Notes, labels, calls and pending
///   history requests all have a number the app already fetches. Without it
///   the sheet gives no hint whether a screen has anything in it.
Future<void> showChatActionsSheet(
  BuildContext context, {
  required String contactUid,
  required String name,
  String? phone,
  MessageChannel channel = MessageChannel.whatsapp,
  VoidCallback? onCall,
  VoidCallback? onStatus,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // isScrollControlled lets the sheet fill the screen, and this one is long
    // enough to want to — which put the title under the status-bar clock. A
    // cap leaves the conversation visible above it, which is also how the
    // frame draws it.
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.88,
    ),
    // No drag handle: the frame closes this with an explicit ✕, and a handle
    // as well is two affordances for one job.
    showDragHandle: false,
    builder: (BuildContext sheetContext) => _ChatActionsSheet(
      contactUid: contactUid,
      name: name,
      phone: phone,
      channel: channel,
      onCall: onCall,
      onStatus: onStatus,
    ),
  );
}

/// Closes the sheet, then navigates.
///
/// Popping first matters: the destination is pushed onto the route below the
/// sheet, so leaving the sheet up would put it back over the new screen when
/// that screen pops.
void _go(BuildContext context, String route) {
  Navigator.of(context).pop();
  context.push(route);
}

class _ChatActionsSheet extends ConsumerWidget {
  const _ChatActionsSheet({
    required this.contactUid,
    required this.name,
    this.phone,
    this.channel = MessageChannel.whatsapp,
    this.onCall,
    this.onStatus,
  });

  final String contactUid;
  final String name;
  final String? phone;
  final MessageChannel channel;
  final VoidCallback? onCall;
  final VoidCallback? onStatus;

  /// A count, or null when there is nothing to say.
  ///
  /// Null rather than "0" for both the unloaded and the empty case: a sheet
  /// that flashes 0 and then 3 is worse than one that shows nothing for a
  /// beat, and "0" beside a row is noise.
  static String? _count(int? n) => n == null || n == 0 ? null : '$n';

  Future<void> _toggleFavourite(
    BuildContext context,
    WidgetRef ref,
    Contact contact,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool want = !contact.isFavorite;

    try {
      final Contact updated = await ref
          .read(contactRepositoryProvider)
          .update(contactUid, favorite: want);
      ref.invalidate(contactDetailProvider(contactUid));

      // The response is checked rather than assumed. `favorite` is read back
      // from every contact payload, but nothing confirms the controller accepts
      // it on write — and a star that flips in the UI then reverts on the next
      // load is the worst of both.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            updated.isFavorite == want
                ? (want ? l10n.caFavouriteOn : l10n.caFavouriteOff)
                : l10n.caFavouriteUnsupported,
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    final Contact? contact =
        ref.watch(contactDetailProvider(contactUid)).valueOrNull;
    final int? noteCount =
        ref.watch(notesProvider(contactUid)).valueOrNull?.length;
    final int? labelCount = contact?.labels.length;
    final int? callCount =
        ref.watch(callHistoryProvider(contactUid)).valueOrNull?.calls.length;
    final HistoryAccessSnapshot? access =
        ref.watch(historyAccessProvider(contactUid)).valueOrNull;
    final int pending = access?.pending.length ?? 0;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppDimens.gutter,
                end: 8,
                bottom: 12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.caTitle,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (name.isNotEmpty)
                          Text(
                            phone == null ? name : '$name · $phone',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                  _CloseButton(onTap: () => Navigator.of(context).pop()),
                ],
              ),
            ),

            // The four quick actions. Favourite is the only one carrying state,
            // so it is the only one drawn selected.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.stripGutter - 4,
              ),
              child: Row(
                children: <Widget>[
                  _QuickTile(
                    label: l10n.caFavourite,
                    icon: (contact?.isFavorite ?? false)
                        ? Icons.star
                        : Icons.star_outline,
                    tint: AppColor.warning,
                    selected: contact?.isFavorite ?? false,
                    // Disabled until the contact is known: otherwise the tile
                    // would post a toggle against a state it has not read.
                    onTap: contact == null
                        ? null
                        : () => _toggleFavourite(context, ref, contact),
                  ),
                  _QuickTile(
                    label: l10n.caCall,
                    icon: Icons.call,
                    tint: AppColor.success,
                    onTap: onCall == null
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            onCall!();
                          },
                  ),
                  _QuickTile(
                    label: l10n.caStatus,
                    icon: Icons.adjust,
                    tint: AppColor.info,
                    onTap: onStatus == null
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            onStatus!();
                          },
                  ),
                  _QuickTile(
                    label: l10n.caAssignShort,
                    icon: Icons.person_add_alt_1,
                    tint: AppColor.success,
                    onTap: () => _go(context, AppRoutes.chatAssign(contactUid)),
                  ),
                ],
              ),
            ),

            SectionLabel(l10n.caGroupConversation),
            ActionSheetRow(
              label: l10n.caInternalNote,
              icon: Icons.edit_outlined,
              tint: AppColor.warning,
              trailingLabel: _count(noteCount),
              onTap: () {
                Navigator.of(context).pop();
                context.push(AppRoutes.chatNotes(contactUid));
              },
            ),
            ActionSheetRow(
              label: l10n.caSnooze,
              icon: Icons.bedtime_outlined,
              tint: AppColor.info,
              onTap: () => _go(context, AppRoutes.chatSnooze(contactUid)),
            ),
            // Transfer sits under Assign's tile for the same reason it used to
            // sit beside its row: the two are easy to mistake, and the
            // difference is consequential — a transfer is a request subject to
            // approval, an assignment takes effect at once.
            ActionSheetRow(
              label: l10n.caTransfer,
              icon: Icons.arrow_outward,
              tint: AppColor.info,
              onTap: () => _go(context, AppRoutes.chatTransfer(contactUid)),
            ),
            ActionSheetRow(
              label: l10n.caQualityReview,
              icon: Icons.star_outline,
              tint: AppColor.warning,
              onTap: () => _go(context, AppRoutes.chatReview(contactUid)),
            ),
            ActionSheetRow(
              label: l10n.caLabels,
              icon: Icons.local_offer_outlined,
              tint: AppColor.success,
              trailingLabel: _count(labelCount),
              onTap: () => _go(context, AppRoutes.chatLabels(contactUid)),
            ),

            SectionLabel(l10n.caGroupMessaging),
            ActionSheetRow(
              label: l10n.caSendTemplate,
              icon: Icons.send_outlined,
              tint: AppColor.success,
              onTap: () => _go(context, AppRoutes.chatTemplate(contactUid)),
            ),
            ActionSheetRow(
              label: l10n.caReminder,
              icon: Icons.notifications_outlined,
              tint: AppColor.warning,
              onTap: () => _go(context, AppRoutes.chatReminder(contactUid)),
            ),
            // Instagram's structured sends have no WhatsApp equivalent, and
            // posting one at a WhatsApp thread answers 422. That is a correct
            // server guard rather than a state the UI should reach, so the row
            // only exists on an Instagram conversation.
            if (channel.isInstagram)
              ActionSheetRow(
                label: l10n.igTitle,
                icon: Icons.dynamic_feed_outlined,
                tint: MessageChannel.instagram.badgeColor,
                onTap: () => _go(context, AppRoutes.chatInstagram(contactUid)),
              ),

            SectionLabel(l10n.caGroupCalling),
            ActionSheetRow(
              label: l10n.caCallHistory,
              icon: Icons.call_outlined,
              tint: AppColor.success,
              trailingLabel: _count(callCount),
              onTap: () => _go(context, AppRoutes.chatCalls(contactUid)),
            ),
            ActionSheetRow(
              label: l10n.caRequestCall,
              icon: Icons.vpn_key_outlined,
              tint: AppColor.info,
              onTap: () =>
                  _go(context, AppRoutes.chatCallPermission(contactUid)),
            ),

            SectionLabel(l10n.caGroupAccess),
            ActionSheetRow(
              label: l10n.caHistoryAccess,
              icon: Icons.lock_outline,
              tint: AppColor.inkMuted,
              // Only when somebody is actually waiting — this is the one count
              // that is a call to action rather than a size.
              trailingLabel: pending == 0 ? null : l10n.caPending(pending),
              onTap: () =>
                  _go(context, AppRoutes.chatHistoryAccess(contactUid)),
            ),
            ActionSheetRow(
              label: l10n.caClearHistory,
              icon: Icons.delete_outline,
              destructive: true,
              onTap: () => _go(context, '/chats/$contactUid/clear-history'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// One of the four actions across the top of the sheet.
class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.label,
    required this.icon,
    required this.tint,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // A tile with no handler is faded rather than hidden: the row is four-up in
    // the frame, and dropping one would reflow the other three.
    final bool enabled = onTap != null;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusCardLarge),
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected ? tint.withValues(alpha: 0.10) : Colors.white,
                borderRadius:
                    BorderRadius.circular(AppDimens.radiusCardLarge),
                border: Border.all(
                  color: selected ? tint : AppColor.hairline,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 22, color: tint),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? tint : AppColor.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheet's ✕.
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: MaterialLocalizations.of(context).closeButtonLabel,
      icon: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColor.surfaceAlt,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, size: 17, color: AppColor.inkMuted),
      ),
    );
  }
}
