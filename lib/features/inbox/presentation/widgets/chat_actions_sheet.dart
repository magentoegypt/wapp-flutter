import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/channel.dart';

/// Chat actions — Figma 330:15.
///
/// The only modal surface in the inventory. Everything else that looks like it
/// might be a sheet (internal notes in particular) is a pushed full page.
Future<void> showChatActionsSheet(
  BuildContext context, {
  required String contactUid,
  required String name,
  String? phone,
  MessageChannel channel = MessageChannel.whatsapp,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => _ChatActionsSheet(
      contactUid: contactUid,
      name: name,
      phone: phone,
      channel: channel,
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

class _ChatActionsSheet extends StatelessWidget {
  const _ChatActionsSheet({
    required this.contactUid,
    required this.name,
    this.phone,
    this.channel = MessageChannel.whatsapp,
  });

  final String contactUid;
  final String name;
  final String? phone;
  final MessageChannel channel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppDimens.gutter,
                end: AppDimens.gutter,
                bottom: 10,
              ),
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
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
            const Divider(),

            ActionSheetRow(
              label: l10n.caInternalNote,
              icon: Icons.sticky_note_2_outlined,
              tint: AppColor.warning,
              onTap: () {
                Navigator.of(context).pop();
                context.push(AppRoutes.chatNotes(contactUid));
              },
            ),
            // Every row below used to dismiss with "not available in the app
            // yet — use the web console". That was true when the mobile API
            // exposed five conversation endpoints; it now exposes all of these,
            // so the rows navigate and the apology string is gone.
            ActionSheetRow(
              label: l10n.caSnooze,
              icon: Icons.snooze_outlined,
              tint: AppColor.info,
              onTap: () => _go(context, AppRoutes.chatSnooze(contactUid)),
            ),
            ActionSheetRow(
              label: l10n.caAssign,
              icon: Icons.person_add_alt,
              tint: AppColor.success,
              onTap: () => _go(context, AppRoutes.chatAssign(contactUid)),
            ),
            // Transfer sits next to Assign because the two are easy to mistake
            // for each other, and the difference is consequential: a transfer
            // is a request subject to approval, an assignment takes effect at
            // once. Adjacency lets the labels do that work.
            ActionSheetRow(
              label: l10n.caTransfer,
              icon: Icons.swap_horiz,
              tint: AppColor.success,
              onTap: () => _go(context, AppRoutes.chatTransfer(contactUid)),
            ),
            ActionSheetRow(
              label: l10n.caLabels,
              icon: Icons.label_outline,
              tint: AppColor.info,
              onTap: () => _go(context, AppRoutes.chatLabels(contactUid)),
            ),
            ActionSheetRow(
              label: l10n.caQualityReview,
              icon: Icons.star_outline,
              tint: AppColor.warning,
              onTap: () => _go(context, AppRoutes.chatReview(contactUid)),
            ),
            // Instagram's structured sends have no WhatsApp equivalent, and
            // posting one at a WhatsApp thread answers 422. That is a correct
            // server guard rather than a state the UI should reach, so the row
            // only exists on an Instagram conversation.
            if (channel.isInstagram)
              ActionSheetRow(
                label: l10n.igTitle,
                icon: Icons.dynamic_feed_outlined,
                tint: const Color(0xFFE0356C),
                onTap: () => _go(context, AppRoutes.chatInstagram(contactUid)),
              ),
            ActionSheetRow(
              label: l10n.caSendTemplate,
              icon: Icons.send_outlined,
              tint: AppColor.info,
              onTap: () => _go(context, AppRoutes.chatTemplate(contactUid)),
            ),
            ActionSheetRow(
              label: l10n.caReminder,
              icon: Icons.alarm_add_outlined,
              tint: AppColor.warning,
              onTap: () => _go(context, AppRoutes.chatReminder(contactUid)),
            ),
            // The three call/history rows are one neutral group in the frame.
            // Tinting two of them green and blue implied a state or severity
            // they do not carry, and split a group the frame reads as one.
            ActionSheetRow(
              label: l10n.caCallHistory,
              icon: Icons.call_outlined,
              tint: AppColor.inkMuted,
              onTap: () => _go(context, AppRoutes.chatCalls(contactUid)),
            ),
            ActionSheetRow(
              label: l10n.caRequestCall,
              icon: Icons.perm_phone_msg_outlined,
              tint: AppColor.inkMuted,
              onTap: () =>
                  _go(context, AppRoutes.chatCallPermission(contactUid)),
            ),
            ActionSheetRow(
              label: l10n.caHistoryAccess,
              icon: Icons.history,
              tint: AppColor.inkMuted,
              onTap: () =>
                  _go(context, AppRoutes.chatHistoryAccess(contactUid)),
            ),
            ActionSheetRow(
              label: l10n.caClearHistory,
              icon: Icons.delete_outline,
              destructive: true,
              onTap: () => _go(context, '/chats/$contactUid/clear-history'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
