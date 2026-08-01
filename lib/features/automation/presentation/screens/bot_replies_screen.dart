import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/bot_reply_repository.dart';

/// Keyword auto-replies — no frame.
///
/// Lists **standalone** replies only. That is the server's own default for
/// `GET /bot-replies` without `?flow=`: replies belonging to a flow are edited
/// through the flow, not on their own, and mixing them into one list would
/// invite editing a node out of context.
class BotRepliesScreen extends ConsumerWidget {
  const BotRepliesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppHeader.back(title: l10n.brTitle),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-bot-replies',
        onPressed: () => context.push(AppRoutes.botReplyNew),
        child: const Icon(Icons.add),
      ),
      body: AsyncValueView<List<BotReply>>(
        value: ref.watch(botReplyListProvider),
        onRetry: () => ref.invalidate(botReplyListProvider),
        builder: (List<BotReply> items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.smart_toy_outlined,
              title: l10n.brEmpty,
              message: l10n.brEmptyHint,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(botReplyListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: AppDimens.fabClearance),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const Divider(indent: AppDimens.gutter),
              itemBuilder: (BuildContext context, int i) {
                final BotReply r = items[i];
                return AppListTile(
                  title: r.name,
                  // What fires it is the useful second line — the reply text is
                  // often long and the trigger is what distinguishes two rows.
                  subtitle: triggerLabel(l10n, r.trigger) +
                      (r.keyword == null ? '' : ' · ${r.keyword}'),
                  subtitleMaxLines: 2,
                  leading: const IconTile(
                    icon: Icons.smart_toy_outlined,
                    color: AppColor.info,
                  ),
                  showChevron: r.messageKind.isEditable,
                  // Two things the row has to say without being opened: a reply
                  // that is switched off answers nobody, and one this screen
                  // cannot edit needs the console. Off wins the single slot —
                  // it is the one that changes whether the reply runs at all.
                  trailing: !r.active
                      ? StatusPill(
                          label: l10n.brInactive,
                          tone: StatusTone.neutral,
                        )
                      : (r.messageKind.isEditable
                          ? null
                          : StatusPill(
                              label: kindLabel(l10n, r.messageKind),
                              tone: StatusTone.info,
                              showDot: false,
                            )),
                  onTap: () => context.push(AppRoutes.botReply(r.uid)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Names what a rich reply sends, so the pill says why the row is locked
/// rather than showing an ellipsis that could mean anything.
String kindLabel(AppLocalizations l10n, BotMessageKind k) => switch (k) {
      BotMessageKind.interactive => l10n.brKindInteractive,
      BotMessageKind.media => l10n.brKindMedia,
      BotMessageKind.simple || BotMessageKind.other => l10n.brKindOther,
    };

String triggerLabel(AppLocalizations l10n, BotTrigger t) => switch (t) {
      BotTrigger.welcome => l10n.brTriggerWelcome,
      BotTrigger.adsWelcome => l10n.brTriggerAdsWelcome,
      BotTrigger.is_ => l10n.brTriggerIs,
      BotTrigger.startsWith => l10n.brTriggerStartsWith,
      BotTrigger.endsWith => l10n.brTriggerEndsWith,
      BotTrigger.containsWord => l10n.brTriggerContainsWord,
      BotTrigger.contains => l10n.brTriggerContains,
    };
