import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/conversation_repository.dart';
import '../../domain/reply_lock.dart';

/// The strip above the composer saying who is replying.
///
/// It used to render only the unlocked case: the moment a teammate actually
/// took the lock, the strip vanished. So the one state it existed to warn
/// about — *somebody else is typing to this customer right now* — was the one
/// state that showed nothing at all, and two agents could answer over each
/// other with the screen looking completely normal.
///
/// Four states now, and the take-over affordance appears only when the server
/// says this agent may use it.
class ReplyLockStrip extends ConsumerWidget {
  const ReplyLockStrip({required this.contactUid, super.key});

  final String contactUid;

  Future<void> _takeover(BuildContext context, WidgetRef ref, String who) async {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // Confirmed, because it is visible to the other agent: their lock is
    // released and their half-typed reply is now a race. Cheap to confirm,
    // rude to do silently.
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: Text(l10n.chatTakeOverTitle),
            content: Text(l10n.chatTakeOverBody(who)),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: Text(MaterialLocalizations.of(c).cancelButtonLabel),
              ),
              TextButton(
                onPressed: () => Navigator.of(c).pop(true),
                child: Text(l10n.chatTakeOver),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(conversationRepositoryProvider)
          .takeoverReplyLock(contactUid);
      ref.invalidate(replyLockProvider(contactUid));
      messenger.showSnackBar(SnackBar(content: Text(l10n.chatTakenOver)));
    } catch (e) {
      // 403 when the permission was revoked between the read and the tap. The
      // server's wording is better than a generic failure here — it names the
      // manager requirement.
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A failed or pending lock read falls back to free rather than an error
    // strip: this is advisory, and the composer works regardless of what it
    // says.
    final ReplyLock lock =
        ref.watch(replyLockProvider(contactUid)).valueOrNull?.atNow() ??
            ReplyLock.free;

    return ReplyLockBanner(
      lock: lock,
      onTakeover: () => _takeover(context, ref, lock.lockedByName ?? ''),
    );
  }
}

/// The strip itself, with no provider behind it.
///
/// Separate so all four states can be rendered from fixtures in
/// `/dev/gallery` — three of them need another agent to be holding the lock,
/// which cannot be arranged from one device.
class ReplyLockBanner extends StatelessWidget {
  const ReplyLockBanner({required this.lock, this.onTakeover, super.key});

  final ReplyLock lock;
  final VoidCallback? onTakeover;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    if (!lock.locked) {
      return AppBanner(
        message: l10n.chatReplyLockOpen,
        // Brand, not neutral: the frame draws this strip as green text on a
        // pale green wash. Neutral rendered it grey-on-grey, which read as
        // disabled chrome rather than as "this chat is free to take".
        tone: BannerTone.brand,
        // 7% brand, per the spec — lighter than the standard brand wash.
        background: AppColor.brand.withValues(alpha: 0.07),
        icon: Icons.lock_open_outlined,
      );
    }

    if (lock.lockedByCurrentUser) {
      return AppBanner(
        message: l10n.chatReplyLockMine,
        tone: BannerTone.brand,
        icon: Icons.lock_outline,
      );
    }

    // The name is usually present, but the engine falls back to a generic
    // display name and could return an empty one — a strip reading "  is
    // replying now." is worse than one that does not name anybody.
    final String? who = lock.lockedByName;
    final String message = who == null
        ? l10n.chatReplyLockSomeone
        : l10n.chatReplyLockHeld(who);

    return Container(
      width: double.infinity,
      color: AppColor.warningWash,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppDimens.stripGutter,
        vertical: 8,
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.lock_outline, size: 17, color: AppColor.warning),
          const SizedBox(width: 8),
          // One line, same as AppBanner — this strip carries a name, so it is
          // the one most likely to wrap.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                message,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(fontSize: 13, color: AppColor.warning),
              ),
            ),
          ),
          // Offered only when the server said so. The rule is admin OR one of
          // three team-structure permissions, and re-deriving it from the role
          // string would drift from the engine the moment that set changed.
          if (lock.canTakeover)
            TextButton(
              onPressed: onTakeover,
              style: TextButton.styleFrom(
                foregroundColor: AppColor.warning,
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(l10n.chatTakeOver),
            ),
        ],
      ),
    );
  }
}
