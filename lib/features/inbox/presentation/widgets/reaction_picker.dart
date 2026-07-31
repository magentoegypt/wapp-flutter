import 'package:flutter/material.dart';

import '../../../../app/theme/app_dimens.dart';
import '../../../../l10n/app_localizations.dart';

/// The reactions Instagram supports.
///
/// A fixed set rather than a full emoji keyboard: Instagram accepts only these
/// on a message, and offering an arbitrary picker would let an agent choose one
/// that comes back rejected.
const List<String> kInstagramReactions = <String>[
  '❤️', '😂', '😮', '😢', '😡', '👍', '👎',
];

/// Long-press reaction picker.
///
/// Instagram-only: there is no WhatsApp equivalent endpoint, so the chat screen
/// only opens this on an Instagram thread rather than showing a row that
/// answers 422.
Future<String?> showReactionPicker(BuildContext context) {
  return showModalBottomSheet<String?>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      final AppLocalizations l10n = AppLocalizations.of(sheetContext);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppDimens.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                l10n.igReactTitle,
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              // Wraps rather than scrolls: seven fit on any phone width, and a
              // horizontal scroller would hide options behind a gesture.
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final String emoji in kInstagramReactions)
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.of(sheetContext).pop(emoji),
                      child: Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(sheetContext).colorScheme.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}
