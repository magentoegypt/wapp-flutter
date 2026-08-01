import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../l10n/app_localizations.dart';

/// Horizontal row of canned-reply suggestions, sitting directly above the
/// composer in the chat frame.
class QuickReplyChips extends StatelessWidget {
  const QuickReplyChips({
    required this.replies,
    required this.onSelected,
    super.key,
  });

  final List<String> replies;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (replies.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      // 32 for the chip plus 14 top and bottom. Sized to the padding rather
      // than the other way round — at 48 the 14dp inset clipped the chips.
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // 14 all round, per the spec. The row used to take the 22 screen
        // gutter horizontally and 4 vertically, so the chips sat inset from
        // the bubbles above them and almost touched the composer below.
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppDimens.stripGutter,
          vertical: 14,
        ),
        itemCount: replies.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) => ActionChip(
          label: Text(replies[i]),
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColor.brandDeep,
          ),
          // Outlined, per the frame (37:1032): a green hairline on the page
          // background, not a filled wash. Filled chips read as the selected
          // state of a filter bar — these are actions, and the inbox's own
          // filter chips directly above them *are* filled, so the two were
          // saying the same thing about different behaviour.
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: AppColor.brandDeep, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          onPressed: () => onSelected(replies[i]),
        ),
      ),
    );
  }
}

/// The message input row: attachment affordance, expanding field, send button.
///
/// Note the composer stays **enabled** even when the 24-hour service window has
/// closed — the handoff requires this. Sending outside the window switches to a
/// template message rather than being blocked outright, so disabling the field
/// here would strand the agent.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    required this.hintText,
    required this.onSend,
    this.onAttach,
    this.sendIcon = Icons.send_outlined,
    this.sendLabel,
    super.key,
  });

  final String hintText;
  final ValueChanged<String> onSend;
  final VoidCallback? onAttach;

  final IconData sendIcon;

  /// When set, renders a labelled button instead of the circular icon — the
  /// internal-notes variant uses "Add note".
  final String? sendLabel;

  @override
  State<MessageComposer> createState() => MessageComposerState();
}

class MessageComposerState extends State<MessageComposer> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final bool has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Lets the parent drop a quick reply into the field.
  void setText(String value) {
    _controller.text = value;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
  }

  void _send() {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final bool isLight = Theme.of(context).brightness == Brightness.light;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppDimens.stripGutter,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : AppColor.surfaceDark,
          border: Border(
            top: BorderSide(
              color: isLight ? AppColor.hairline : AppColor.hairlineDark,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (widget.onAttach != null)
              IconButton(
                onPressed: widget.onAttach,
                // A paperclip, deliberately departing from the frame, which
                // draws an outlined emoji face here. This button opens the
                // attach sheet — photo, camera, video — and a smiley promises
                // an emoji keyboard the app does not have. Matching the frame's
                // pixels would mean mismatching its meaning.
                icon: const Icon(Icons.attach_file, size: 21),
                color: AppColor.inkMuted,
                tooltip: AppLocalizations.of(context).attachTitle,
              ),
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (widget.sendLabel != null)
              FilledButton(
                onPressed: _hasText ? _send : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(widget.sendLabel!),
              )
            else
              _SendButton(enabled: _hasText, icon: widget.sendIcon, onTap: _send),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.icon,
    required this.onTap,
  });

  final bool enabled;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // Green in both states, per the frame — which draws it green with
          // the placeholder still showing. Grey read as broken rather than as
          // "nothing to send yet". Faded rather than fully lit so an inert
          // button does not look like a live one.
          color: enabled
              ? AppColor.brand
              : AppColor.brand.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 19, color: Colors.white),
      ),
    );
  }
}
