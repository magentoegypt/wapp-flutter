import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_header.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../core/widgets/initials_avatar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../inbox/data/conversation_repository.dart';
import '../../../inbox/domain/conversation.dart';
import '../../data/conversation_action_repository.dart';

/// Clear chat history — the one screen in the app that destroys shared data.
///
/// `clearHistory` deletes the stored message log for this contact **for the
/// whole workspace and every agent**, with no undo. The obvious misreading is
/// "clear it off my screen", and an agent who acts on that misreading wipes a
/// record their colleagues and their compliance team depend on. Three things
/// guard against it, and none of them is decoration:
///
/// * the warning banner states the blast radius in the first sentence;
/// * the contact whose log is about to go is named on screen, because this
///   route is reachable from a sheet two screens deep and "which chat am I in"
///   is exactly the question a tired agent skips;
/// * the destructive button stays disabled until the confirmation word has been
///   typed out in full, so the action cannot be reached by tapping through.
class ClearHistoryScreen extends ConsumerStatefulWidget {
  const ClearHistoryScreen({required this.contactUid, super.key});

  final String contactUid;

  @override
  ConsumerState<ClearHistoryScreen> createState() => _ClearHistoryScreenState();
}

class _ClearHistoryScreenState extends ConsumerState<ClearHistoryScreen> {
  /// Owned by the State rather than raised through `showTextPromptDialog`: that
  /// helper answers once, on dismissal, and the gate here has to be re-evaluated
  /// on every keystroke to drive the button's enabled state. Owning it here also
  /// keeps the controller's lifetime tied to the field's, which is what the
  /// helper exists to guarantee — a controller disposed beside a still-animating
  /// dialog is what threw `'_dependents.isEmpty'` twice in this repo.
  final TextEditingController _confirmation = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _clear() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _busy = true);

    try {
      await ref
          .read(conversationActionRepositoryProvider)
          .clearHistory(widget.contactUid);

      // Everything cached downstream is now a lie: the thread still holds
      // messages the server no longer has, and the inbox row still previews the
      // last of them. Refetched rather than patched — the deletion is
      // workspace-wide, so the client's copy is not a subset it can amend.
      ref.invalidate(chatThreadProvider(widget.contactUid));
      ref.invalidate(inboxListProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.clrDone)));
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
    final ChatThread? thread =
        ref.watch(chatThreadProvider(widget.contactUid)).valueOrNull;

    final String typed = _confirmation.text.trim();
    // Case-sensitive, deliberately: "clear" is a word an agent might type by
    // reflex, "CLEAR" is a word they had to read the instruction to produce.
    // Surrounding whitespace is trimmed first — a trailing space from a soft
    // keyboard is invisible, so rejecting it would read as a broken field
    // rather than as a safety catch.
    final bool matches = typed == l10n.clrConfirmWord;
    final bool mismatch = typed.isNotEmpty && !matches;

    return Scaffold(
      appBar: AppHeader.back(title: l10n.clrTitle),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Named target first, then the consequence — in that order the
            // banner's "this contact" has an antecedent on screen. The row does
            // not navigate; it is here to be read.
            if (thread != null)
              AppListTile(
                title: thread.name,
                subtitle: thread.phone,
                leading: InitialsAvatar(name: thread.name),
                showChevron: false,
              ),
            AppBanner(
              message: l10n.clrWarning,
              tone: BannerTone.warning,
              icon: Icons.warning_amber_rounded,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppDimens.gutter),
                children: <Widget>[
                  Text(
                    l10n.clrConfirmPrompt,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmation,
                    enabled: !_busy,
                    // Autocorrect and suggestion strips rewrite short all-caps
                    // tokens; a keyboard that "fixes" CLEAR into Clear would
                    // leave the agent staring at a button that will not enable.
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    // Rebuilds the button's enabled state as the word is typed.
                    onChanged: (String _) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: l10n.clrConfirmWord,
                      errorText: mismatch ? l10n.clrMismatch : null,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppDimens.gutter),
              child: Column(
                children: <Widget>[
                  FilledButton(
                    onPressed: (matches && !_busy) ? _clear : null,
                    // Solid danger, not the brand fill: this button does not
                    // save anything. Its disabled face is the danger wash, so a
                    // locked button still reads as the destructive one rather
                    // than as a greyed-out Save.
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColor.danger,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColor.dangerWash,
                      disabledForegroundColor: AppColor.inkFaint,
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(l10n.clrSubmit),
                  ),
                  const SizedBox(height: 4),
                  // An explicit way out, level with the destructive control.
                  // Backing out of this screen should never depend on finding
                  // the header's arrow.
                  TextButton(
                    onPressed: _busy ? null : () => context.pop(),
                    child: Text(l10n.actionCancel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
