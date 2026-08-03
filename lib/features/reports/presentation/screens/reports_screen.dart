import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../l10n/app_localizations.dart';

/// Reports hub — no frame; these endpoints arrived after the handoff was drawn.
///
/// A hub rather than four rows directly in More, because these are the only
/// analytics in the app and grouping them keeps More's list at the length the
/// frame draws.
///
/// Every destination is read-only. That makes this the one module that can be
/// walked end-to-end against production without writing anything, which is why
/// it is also the module worth checking on a real workspace rather than from
/// fixtures.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.rpTitle),
      body: ListView(
        children: <Widget>[
          AppListTile(
            title: l10n.rpConversational,
            subtitle: l10n.rpConversationalHint,
            leading: const IconTile(
              icon: Icons.insights_outlined,
              color: AppColor.brandDeep,
            ),
            onTap: () => context.push(AppRoutes.reportConversational),
          ),
          const Divider(indent: 0),
          AppListTile(
            title: l10n.rpPauseReasons,
            subtitle: l10n.rpPauseReasonsHint,
            leading: const IconTile(
              icon: Icons.pause_circle_outline,
              color: AppColor.warning,
            ),
            onTap: () => context.push(AppRoutes.reportPauseReasons),
          ),
          const Divider(indent: 0),
          AppListTile(
            title: l10n.rpQuality,
            subtitle: l10n.rpQualityHint,
            leading: const IconTile(
              icon: Icons.star_outline,
              color: AppColor.info,
            ),
            onTap: () => context.push(AppRoutes.reportQuality),
          ),
          const Divider(indent: 0),
          AppListTile(
            title: l10n.rpTargets,
            subtitle: l10n.rpTargetsHint,
            leading: const IconTile(
              icon: Icons.flag_outlined,
              color: AppColor.success,
            ),
            onTap: () => context.push(AppRoutes.reportTargets),
          ),
        ],
      ),
    );
  }
}
