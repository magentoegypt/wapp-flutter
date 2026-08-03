/// The pieces Contact detail and Conversation info both draw.
///
/// The two screens render the same customer from two entry points and had
/// grown their own copies of every part of it — which is how Message ended up
/// wearing a speech bubble on one and an envelope on the other, and how one
/// got white surfaces and dividers while the other stayed flat. One definition
/// each, used twice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/error/failure.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../conversation_actions/data/conversation_action_repository.dart';
import '../../data/contact_repository.dart';
import '../../domain/contact.dart';

/// One brand-wash tile in the three-up action row.
///
/// Returns an [Expanded], so drop these straight into a [Row] — wrapping one
/// again double-flexes it.
class ActionTile extends StatelessWidget {
  const ActionTile({
    required this.icon,
    required this.label,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    // brandDeep for the glyph and label, not brand: brand green is a fill
    // colour and does not reach AA as text on the wash.
    final Color ink = enabled ? AppColor.brandDeep : AppColor.inkFaint;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: enabled ? AppColor.brandWash : AppColor.surfaceAlt,
            borderRadius: BorderRadius.circular(AppDimens.radiusCard),
          ),
          child: Column(
            children: <Widget>[
              Icon(icon, size: 22, color: ink),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Favourite action tile.
///
/// Optimistic: the star flips immediately and is corrected from the response,
/// because the round trip is long enough that a tile which does nothing for a
/// second reads as broken. On failure it flips back and says so — silently
/// reverting would look like the tap missed.
class FavouriteTile extends ConsumerStatefulWidget {
  const FavouriteTile({required this.contact, super.key});

  final Contact contact;

  @override
  ConsumerState<FavouriteTile> createState() => _FavouriteTileState();
}

class _FavouriteTileState extends ConsumerState<FavouriteTile> {
  bool? _override;
  bool _busy = false;

  bool get _on => _override ?? widget.contact.isFavorite;

  Future<void> _toggle() async {
    if (_busy) return;
    final bool previous = _on;
    setState(() {
      _busy = true;
      _override = !previous;
    });

    try {
      final bool now = await ref
          .read(conversationActionRepositoryProvider)
          .toggleFavourite(widget.contact.uid);
      if (!mounted) return;
      // The server's answer wins over the optimistic guess.
      setState(() => _override = now);
      ref.invalidate(contactDetailProvider(widget.contact.uid));
      ref.invalidate(contactListProvider);
    } on Failure catch (e) {
      if (!mounted) return;
      setState(() => _override = previous);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ActionTile(
      icon: _on ? Icons.star : Icons.star_outline,
      label: AppLocalizations.of(context).cdFavorite,
      onTap: _toggle,
    );
  }
}

/// A full-bleed white block on the tinted page.
///
/// The frame is a white sheet interrupted by tinted bands — the section
/// headings sit on the page colour and everything else sits on white. Without
/// this a screen is one flat tone, so the headings float and there is nothing
/// for a divider to separate.
///
/// [divided] draws a hairline between children, inset past the gutter so the
/// rules line up under the values rather than running edge to edge.
class Surface extends StatelessWidget {
  const Surface({required this.children, this.divided = false, super.key});

  final List<Widget> children;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    final List<Widget> rows = <Widget>[];

    for (int i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (divided && i < children.length - 1) {
        rows.add(Divider(
          height: 1,
          thickness: 1,
          indent: AppDimens.gutter,
          endIndent: AppDimens.gutter,
          color: isLight ? AppColor.hairline : AppColor.hairlineDark,
        ));
      }
    }

    return Container(
      width: double.infinity,
      color: isLight ? Colors.white : AppColor.surfaceDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }
}

/// One label/value line, or null when there is no value.
///
/// Null rather than an empty box so a caller can drop it with the null-aware
/// element operator: a row that renders nothing is still a child, and inside a
/// divided [Surface] that draws a rule against an invisible row.
Widget? infoRow(String label, String? value, {String? secondary}) {
  if (value == null || value.isEmpty) return null;
  return InfoRow(label: label, value: value, secondary: secondary);
}

/// The frame reads these as a data table: label left, value right, no leading
/// tile and no chevron. Borrowing the list-row idiom made read-only data look
/// like tappable settings.
class InfoRow extends StatelessWidget {
  const InfoRow({
    required this.label,
    required this.value,
    this.secondary,
    super.key,
  });

  final String label;
  final String value;

  /// A quieter second line under [value] — the Instagram handle under the
  /// channel name. It qualifies the value rather than standing beside it.
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppDimens.gutter,
        vertical: 13,
      ),
      child: Row(
        children: <Widget>[
          // The label takes its own width and no more. As `Expanded` it
          // claimed the row and squeezed the value, which is why a long
          // address broke mid-token instead of sitting on one line.
          Text(
            label,
            style: text.bodyLarge?.copyWith(color: AppColor.inkMuted),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                // Scale down rather than wrap or ellipsize. An email is only
                // useful whole: truncating hides the domain, and wrapping
                // splits it at whatever character lands on the edge.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    value,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.end,
                    style: text.bodyLarge?.copyWith(
                      color: AppColor.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (secondary != null)
                  Text(
                    secondary!,
                    textAlign: TextAlign.end,
                    style: text.bodyMedium?.copyWith(color: AppColor.inkMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
