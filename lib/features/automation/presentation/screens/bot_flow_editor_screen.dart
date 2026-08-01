import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/section_label.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/bot_flow_repository.dart';
import '../../data/bot_reply_repository.dart';
import 'bot_replies_screen.dart' show triggerLabel;

/// Create or edit a flow's envelope, and list its steps read-only.
class BotFlowEditorScreen extends ConsumerWidget {
  const BotFlowEditorScreen({this.uid, super.key});

  final String? uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (uid == null) return const _Form(existing: null);

    return AsyncValueView<BotFlow>(
      value: ref.watch(botFlowProvider(uid!)),
      onRetry: () => ref.invalidate(botFlowProvider(uid!)),
      builder: (BotFlow f) => _Form(existing: f),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.existing});

  final BotFlow? existing;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final TextEditingController _title;
  late final TextEditingController _keyword;
  late BotTrigger _trigger;
  late bool _active;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final BotFlow? f = widget.existing;
    _title = TextEditingController(text: f?.title);
    _keyword = TextEditingController(text: f?.keyword);
    _trigger = f?.startTrigger ?? BotTrigger.is_;
    _active = f?.active ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _keyword.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String title = _title.text.trim();
    final String keyword = _keyword.text.trim();

    if (title.isEmpty || (_trigger.needsKeyword && keyword.isEmpty)) {
      _toast(l10n.bfIncomplete);
      return;
    }

    setState(() => _busy = true);
    final GoRouter router = GoRouter.of(context);
    try {
      final BotFlow f = BotFlow(
        uid: widget.existing?.uid ?? '',
        title: title,
        startTrigger: _trigger,
        keyword: _trigger.needsKeyword ? keyword : null,
        active: _active,
        stepCount: widget.existing?.stepCount,
      );
      final BotFlowRepository repo = ref.read(botFlowRepositoryProvider);

      if (_isEdit) {
        await repo.update(widget.existing!.uid, f);
        _toast(l10n.bfSaved);
      } else {
        final String uid = await repo.create(f);
        // The create endpoint drops `active`, so the repository follows with a
        // PUT. If it had no uid to follow up against, the flow exists and is
        // stopped — say that rather than reporting a clean save.
        _toast(_active && uid.isEmpty ? l10n.bfCreatedInactive : l10n.bfSaved);
      }
      ref.invalidate(botFlowListProvider);
      router.pop();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final BotFlow f = widget.existing!;
    // Taken from the steps this screen actually loaded, not from the flow's own
    // count — the list endpoint sends none, so the flow object often has null.
    final int? steps =
        ref.read(botFlowStepsProvider(f.uid)).valueOrNull?.length;

    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            // Names the step count when it is known, because deleting a flow
            // takes its replies with it and the row above only shows the title.
            content: Text(
              steps == null
                  ? l10n.bfDeleteConfirmPlain(f.title)
                  : l10n.bfDeleteConfirm(f.title, steps),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: Text(MaterialLocalizations.of(c).cancelButtonLabel),
              ),
              TextButton(
                onPressed: () => Navigator.of(c).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppColor.danger),
                child: Text(l10n.actionDelete),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    final GoRouter router = GoRouter.of(context);
    try {
      await ref.read(botFlowRepositoryProvider).delete(f.uid);
      ref.invalidate(botFlowListProvider);
      _toast(l10n.bfDeleted);
      router.pop();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final BotFlow? f = widget.existing;

    // Whether this flow has any steps, from the steps actually loaded below. A
    // brand-new flow has none by definition; an existing one is unknown until
    // that request lands, and an unknown must not be reported as empty.
    final int? knownSteps = f == null
        ? 0
        : ref.watch(botFlowStepsProvider(f.uid)).valueOrNull?.length;

    return Scaffold(
      appBar: AppHeader.back(
        title: _isEdit ? l10n.bfEdit : l10n.bfNew,
        actions: <Widget>[
          if (_isEdit)
            IconButton(
              tooltip: l10n.bfDelete,
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.gutter,
              14,
              AppDimens.gutter,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Said before the form, not after a save: the steps are built
                // elsewhere, and someone who fills this in expecting a working
                // bot should know that up front.
                AppBanner(message: l10n.bfConsoleNote, tone: BannerTone.neutral),
                const SizedBox(height: 14),

                TextField(
                  controller: _title,
                  maxLength: BotFlowLimits.title,
                  decoration: InputDecoration(labelText: l10n.bfName),
                ),
                DropdownButtonFormField<BotTrigger>(
                  initialValue: _trigger,
                  decoration: InputDecoration(labelText: l10n.bfTrigger),
                  items: <DropdownMenuItem<BotTrigger>>[
                    for (final BotTrigger t in BotTrigger.values)
                      DropdownMenuItem<BotTrigger>(
                        value: t,
                        child: Text(triggerLabel(l10n, t)),
                      ),
                  ],
                  onChanged: (BotTrigger? v) =>
                      setState(() => _trigger = v ?? _trigger),
                ),
                if (_trigger.needsKeyword)
                  TextField(
                    controller: _keyword,
                    maxLength: BotFlowLimits.keyword,
                    decoration: InputDecoration(labelText: l10n.bfKeyword),
                  ),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (bool v) => setState(() => _active = v),
                  title: Text(l10n.bfActiveLabel),
                  // An empty flow that is switched on triggers and then sends
                  // nothing. The switch still works — this is the workspace's
                  // call — but it does not pass silently. Only warns once the
                  // steps are known to be zero, never while they are still
                  // loading.
                  subtitle: Text(
                    _active && knownSteps == 0
                        ? l10n.bfActiveEmptyHint
                        : l10n.bfActiveHint,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(l10n.actionSave),
                ),
              ],
            ),
          ),

          if (_isEdit) ...<Widget>[
            SectionLabel(l10n.bfStepsLabel),
            _Steps(flowUid: f!.uid),
          ],
        ],
      ),
    );
  }
}

/// The flow's replies, listed but not tappable.
///
/// Opening one would show the standalone reply editor, which knows nothing
/// about the edges pointing at this step — saving from there would rename a
/// node the flow still refers to by its old identity.
class _Steps extends ConsumerWidget {
  const _Steps({required this.flowUid});

  final String flowUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return AsyncValueView<List<BotReply>>(
      value: ref.watch(botFlowStepsProvider(flowUid)),
      onRetry: () => ref.invalidate(botFlowStepsProvider(flowUid)),
      loading: const Padding(
        padding: EdgeInsets.all(AppDimens.gutter),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      builder: (List<BotReply> steps) {
        if (steps.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.gutter,
              vertical: 8,
            ),
            child: Text(
              l10n.bfNoSteps,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        return Column(
          children: <Widget>[
            for (int i = 0; i < steps.length; i++)
              AppListTile(
                // A step inside a flow usually has no name of its own, so the
                // position is the only stable label — and the reply text is
                // what actually identifies it to a reader.
                title: steps[i].name.isEmpty
                    ? l10n.bfStepN(i + 1)
                    : steps[i].name,
                subtitle: steps[i].replyText ?? '',
                subtitleMaxLines: 2,
                showChevron: false,
                leading: IconTile(
                  icon: Icons.subdirectory_arrow_right,
                  color: AppColor.inkMuted,
                ),
              ),
          ],
        );
      },
    );
  }
}
