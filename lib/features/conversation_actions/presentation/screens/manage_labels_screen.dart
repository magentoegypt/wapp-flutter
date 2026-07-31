import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/conversation_action_repository.dart';
import '../../domain/action_models.dart';

/// Manage labels — the conversation's whole label set, edited at once.
///
/// `setLabels` **replaces** rather than appends, so this screen is not "add a
/// label": every tick that is missing when Save is pressed is a removal. That
/// is the one thing a user can get wrong here, and it is why the applied set is
/// mirrored as a live strip of pills above the list — unticking a row visibly
/// takes its pill away in the same frame, which no amount of copy achieves.
class ManageLabelsScreen extends ConsumerStatefulWidget {
  const ManageLabelsScreen({
    required this.contactUid,
    this.initial = const <String>[],
    super.key,
  });

  final String contactUid;

  /// Label uids already on this conversation. Passed in by the caller rather
  /// than fetched: the conversation that opened this screen already holds them,
  /// and a second round trip would let the ticks appear a beat after the rows.
  final List<String> initial;

  @override
  ConsumerState<ManageLabelsScreen> createState() => _ManageLabelsScreenState();
}

class _ManageLabelsScreenState extends ConsumerState<ManageLabelsScreen> {
  late final Set<String> _selected = <String>{...widget.initial};

  bool _busy = false;

  void _toggle(String uid) {
    // remove() answers whether anything went, so one call covers both ways.
    setState(() {
      if (!_selected.remove(uid)) _selected.add(uid);
    });
  }

  Future<void> _save(List<ConversationLabel> known) async {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // Filtered through the fetched list rather than sent straight from the set.
    // Two reasons: it fixes the order to the one on screen, and it drops any
    // uid in `initial` that no longer exists in the workspace — such a label
    // can never be shown as ticked, so silently preserving it would contradict
    // what the user is looking at.
    final List<String> labelUids = known
        .map((ConversationLabel l) => l.uid)
        .where(_selected.contains)
        .toList();

    setState(() => _busy = true);
    try {
      await ref.read(conversationActionRepositoryProvider).setLabels(
            contactUid: widget.contactUid,
            labelUids: labelUids,
          );
      if (!mounted) return;
      // Clearing everything is legitimate, but it is also the outcome a mis-tap
      // produces, so it gets its own acknowledgement — "Labels updated" would
      // read as success on a screen that now has none.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(labelUids.isEmpty ? l10n.lbCleared : l10n.lbDone),
        ),
      );
      context.pop();
    } on Failure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<ConversationLabel>> labels =
        ref.watch(conversationLabelsProvider);
    final List<ConversationLabel> known =
        labels.valueOrNull ?? const <ConversationLabel>[];

    return Scaffold(
      appBar: AppHeader.back(title: l10n.lbTitle),
      body: Column(
        children: <Widget>[
          AppBanner(
            message: l10n.lbPrompt,
            tone: BannerTone.brand,
            icon: Icons.label_outline,
          ),
          _AppliedStrip(
            labels: known.where((ConversationLabel l) => _selected.contains(l.uid)),
          ),
          Expanded(
            child: AsyncValueView<List<ConversationLabel>>(
              value: labels,
              onRetry: () => ref.invalidate(conversationLabelsProvider),
              builder: (List<ConversationLabel> items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.label_outline,
                    title: l10n.lbEmpty,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: items.length,
                  itemBuilder: (BuildContext context, int i) {
                    final ConversationLabel label = items[i];
                    final bool on = _selected.contains(label.uid);
                    return AppListTile(
                      title: label.name,
                      // The row performs a toggle, so it must not promise a
                      // push the way a chevron does.
                      showChevron: false,
                      onTap: _busy ? null : () => _toggle(label.uid),
                      leading: IconTile(
                        icon: on ? Icons.label : Icons.label_outline,
                        color: _labelColor(label.color) ?? AppColor.inkMuted,
                      ),
                      trailing: Checkbox(
                        value: on,
                        onChanged: _busy
                            ? null
                            : (bool? _) => _toggle(label.uid),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // Hidden while the list is unresolved or genuinely empty: saving from
          // either state could only send the caller's `initial` back unchanged,
          // and a workspace with no labels has none to clear.
          if (known.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppDimens.gutter),
                child: FilledButton(
                  onPressed: _busy ? null : () => _save(known),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l10n.lbSubmit),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The set as it will be saved, mirrored above the list.
///
/// Collapses to nothing when the selection is empty — that blank is the clearest
/// possible statement that Save will strip the conversation bare.
class _AppliedStrip extends StatelessWidget {
  const _AppliedStrip({required this.labels});

  final Iterable<ConversationLabel> labels;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColor.hairline)),
      ),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppDimens.gutter,
        vertical: 10,
      ),
      // Capped and scrollable: a conversation carrying a dozen labels would
      // otherwise push the list it is describing off the bottom of the screen.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 92),
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final ConversationLabel l in labels)
                // Neutral for every pill, never a tone derived from the label's
                // own colour: StatusPill's tones encode conversation state, so a
                // label rendered in success green would read as "solved". The
                // workspace hue belongs on the row's icon tile instead.
                StatusPill(
                  label: l.name,
                  tone: StatusTone.neutral,
                  showDot: false,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A workspace label's colour, as an arbitrary hex string from the API.
///
/// Tolerant on purpose — the field is free text server-side and arrives as
/// `#RRGGBB`, bare `RRGGBB`, `AARRGGBB`, or empty. Anything unparseable falls
/// back to muted ink rather than defaulting to a colour that would look
/// deliberate.
Color? _labelColor(String? raw) {
  final String hex = (raw ?? '').trim().replaceFirst('#', '');
  if (hex.length != 6 && hex.length != 8) return null;
  final int? value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  return Color(hex.length == 6 ? 0xFF000000 | value : value);
}
