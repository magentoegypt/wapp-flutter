import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import 'initials_avatar.dart';

/// An internal note on a conversation.
///
/// The sticky-note palette is not decoration — it is the visual cue that this
/// content is **workspace-private**. Notes must never be rendered in a
/// customer-facing surface or folded into a message payload, and keeping them
/// visually unlike a chat bubble is what makes that obvious at a glance. Do not
/// restyle this to match the rest of the app.
class NoteCard extends StatelessWidget {
  const NoteCard({
    required this.author,
    required this.timeLabel,
    required this.body,
    this.edited = false,
    this.onEdit,
    this.onDelete,
    super.key,
  });

  final String author;

  /// Pre-formatted by the caller.
  final String timeLabel;
  final String body;
  final bool edited;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColor.noteFill,
        border: Border.all(color: AppColor.noteLine),
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              InitialsAvatar(name: author, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColor.noteInk,
                      ),
                    ),
                    Text(
                      edited ? '$timeLabel · edited' : timeLabel,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColor.noteInk,
                      ),
                    ),
                  ],
                ),
              ),
              if (onEdit != null)
                _NoteAction(icon: Icons.edit_outlined, onTap: onEdit!),
              if (onDelete != null)
                _NoteAction(icon: Icons.delete_outline, onTap: onDelete!),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: Color(0xFF5B4A00),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteAction extends StatelessWidget {
  const _NoteAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      color: AppColor.noteInk,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
    );
  }
}
