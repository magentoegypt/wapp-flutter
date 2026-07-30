import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../l10n/app_localizations.dart';

/// Chat actions — Figma 330:15.
///
/// The only modal surface in the inventory. Everything else that looks like it
/// might be a sheet (internal notes in particular) is a pushed full page.
Future<void> showChatActionsSheet(
  BuildContext context, {
  required String contactUid,
  required String name,
  String? phone,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => _ChatActionsSheet(
      contactUid: contactUid,
      name: name,
      phone: phone,
    ),
  );
}

class _ChatActionsSheet extends StatelessWidget {
  const _ChatActionsSheet({
    required this.contactUid,
    required this.name,
    this.phone,
  });

  final String contactUid;
  final String name;
  final String? phone;

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
            ActionSheetRow(
              label: l10n.caSnooze,
              icon: Icons.snooze_outlined,
              tint: AppColor.info,
              onTap: () => Navigator.of(context).pop(),
            ),
            ActionSheetRow(
              label: l10n.caTransfer,
              icon: Icons.swap_horiz,
              tint: AppColor.success,
              onTap: () => Navigator.of(context).pop(),
            ),
            ActionSheetRow(
              label: l10n.caQualityReview,
              icon: Icons.star_outline,
              tint: AppColor.warning,
              onTap: () => Navigator.of(context).pop(),
            ),
            ActionSheetRow(
              label: l10n.caSendTemplate,
              icon: Icons.send_outlined,
              tint: AppColor.info,
              onTap: () => Navigator.of(context).pop(),
            ),
            // The three call/history rows are one neutral group in the frame.
            // Tinting two of them green and blue implied a state or severity
            // they do not carry, and split a group the frame reads as one.
            ActionSheetRow(
              label: l10n.caCallHistory,
              icon: Icons.call_outlined,
              tint: AppColor.inkMuted,
              onTap: () => Navigator.of(context).pop(),
            ),
            ActionSheetRow(
              label: l10n.caRequestCall,
              icon: Icons.perm_phone_msg_outlined,
              tint: AppColor.inkMuted,
              onTap: () => Navigator.of(context).pop(),
            ),
            ActionSheetRow(
              label: l10n.caHistoryAccess,
              icon: Icons.history,
              tint: AppColor.inkMuted,
              onTap: () => Navigator.of(context).pop(),
            ),
            ActionSheetRow(
              label: l10n.caClearHistory,
              icon: Icons.delete_outline,
              destructive: true,
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
