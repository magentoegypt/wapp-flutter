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
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppDimens.gutter,
          vertical: 4,
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
          backgroundColor: AppColor.brandWash,
          side: BorderSide.none,
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
    this.sendIcon = Icons.send_rounded,
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
          horizontal: AppDimens.gutter,
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
          color: enabled ? AppColor.brand : AppColor.inkFaint,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}
