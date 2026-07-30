import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// An alert dialog that asks for one piece of text and returns it.
///
/// It exists because the obvious way to write this crashes. Creating a
/// controller beside the `await showDialog(...)` and disposing it on the next
/// line throws `'_dependents.isEmpty': is not true` — the dialog's TextField is
/// still mounted through the pop animation, so the controller still has
/// dependents when dispose runs. Owning the controller in a StatefulWidget ties
/// its lifetime to the field's instead.
///
/// Returns the trimmed text, or null if dismissed or left empty.
Future<String?> showTextPromptDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? message,
  String? hintText,
  String initialValue = '',
  int maxLines = 1,
  TextInputType? keyboardType,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext c) => _TextPromptDialog(
      title: title,
      confirmLabel: confirmLabel,
      message: message,
      hintText: hintText,
      initialValue: initialValue,
      maxLines: maxLines,
      keyboardType: keyboardType,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialValue,
    required this.maxLines,
    this.message,
    this.hintText,
    this.keyboardType,
  });

  final String title;
  final String confirmLabel;
  final String? message;
  final String? hintText;
  final String initialValue;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final String value = _controller.text.trim();
    Navigator.of(context).pop(value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.message != null) ...<Widget>[
            Text(
              widget.message!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: widget.maxLines,
            minLines: widget.maxLines > 1 ? 3 : null,
            keyboardType: widget.keyboardType,
            textInputAction:
                widget.maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
            onSubmitted: widget.maxLines > 1 ? null : (_) => _confirm(),
            decoration: InputDecoration(hintText: widget.hintText),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        TextButton(onPressed: _confirm, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
