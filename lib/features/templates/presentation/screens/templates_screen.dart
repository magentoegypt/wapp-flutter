import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/template_repository.dart';
import '../../domain/whatsapp_template.dart';

/// WhatsApp templates.
///
/// No Figma frame — the More frame lists a Templates row and the screen behind
/// it was never drawn, because until the 31 Jul API pass there were no
/// endpoints to build it against. Follows the app's own list conventions.
class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppHeader.back(
        title: l10n.tplTitle,
        actions: <Widget>[
          IconButton(
            tooltip: l10n.tplSync,
            icon: const Icon(Icons.sync, color: Colors.white),
            onPressed: () => _sync(context, ref, l10n),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-templates',
        onPressed: () => context.push(AppRoutes.templateNew),
        child: const Icon(Icons.add),
      ),
      body: AsyncValueView<List<WhatsAppTemplate>>(
        value: ref.watch(templateListProvider),
        onRetry: () => ref.invalidate(templateListProvider),
        builder: (List<WhatsAppTemplate> items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.article_outlined,
              title: l10n.tplEmpty,
              message: l10n.tplEmptyHint,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(templateListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: AppDimens.fabClearance),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(indent: AppDimens.gutter),
              itemBuilder: (BuildContext context, int i) {
                final WhatsAppTemplate t = items[i];
                final ({String label, StatusTone tone})? badge =
                    _statusBadge(l10n, t.status);

                return AppListTile(
                  title: t.name,
                  // Language and category are what distinguish two templates
                  // with the same name, and both are immutable — so they
                  // identify the row better than the body would.
                  subtitle: '${t.language} · ${_categoryLabel(l10n, t.category)}',
                  showChevron: badge == null,
                  trailing: badge == null
                      ? null
                      : StatusPill(label: badge.label, tone: badge.tone),
                  onTap: () => context.push(AppRoutes.template(t.uid)),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _sync(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final List<WhatsAppTemplate> fresh =
          await ref.read(templateRepositoryProvider).sync();
      ref.invalidate(templateListProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.tplSynced(fresh.length))),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

String _categoryLabel(AppLocalizations l10n, WaTemplateCategory c) =>
    c == WaTemplateCategory.marketing
        ? l10n.tplCategoryMarketing
        : l10n.tplCategoryUtility;

/// Status as a pill. Unknown draws nothing rather than inventing a label for a
/// value this app has not seen.
({String label, StatusTone tone})? _statusBadge(
  AppLocalizations l10n,
  WaTemplateStatus s,
) =>
    switch (s) {
      WaTemplateStatus.approved =>
        (label: l10n.tplStatusApproved, tone: StatusTone.success),
      WaTemplateStatus.pending =>
        (label: l10n.tplStatusPending, tone: StatusTone.warning),
      WaTemplateStatus.rejected =>
        (label: l10n.tplStatusRejected, tone: StatusTone.danger),
      WaTemplateStatus.disabled =>
        (label: l10n.tplStatusDisabled, tone: StatusTone.neutral),
      WaTemplateStatus.unknown => null,
    };
