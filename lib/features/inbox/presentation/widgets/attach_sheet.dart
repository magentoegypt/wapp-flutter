import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimens.dart';
import '../../../../core/widgets/app_banner.dart';
import '../../../../core/widgets/app_list_tile.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/media_repository.dart';
import '../../domain/channel.dart';

/// What the agent picked, before it is uploaded.
class PickedMedia {
  const PickedMedia({
    required this.path,
    required this.fileName,
    required this.kind,
  });

  final String path;
  final String fileName;
  final MediaKind kind;
}

/// Attachment picker.
///
/// Images and video only. Documents need a file picker this app does not carry
/// a dependency for, and the sheet says so rather than offering a row that
/// opens nothing — the alternative was a PDF option that silently did not work
/// on the one channel (Instagram) where PDF is the *only* accepted document
/// format.
Future<PickedMedia?> showAttachSheet(
  BuildContext context, {
  required MessageChannel channel,
}) {
  return showModalBottomSheet<PickedMedia?>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => _AttachSheet(channel: channel),
  );
}

class _AttachSheet extends StatelessWidget {
  const _AttachSheet({required this.channel});

  final MessageChannel channel;

  Future<void> _pick(
    BuildContext context,
    ImageSource source,
    bool video,
  ) async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? file = video
          ? await picker.pickVideo(source: source)
          : await picker.pickImage(source: source);
      if (file == null) return; // cancelled — not an error
      if (!context.mounted) return;
      Navigator.of(context).pop(
        PickedMedia(
          path: file.path,
          fileName: file.name,
          kind: video ? MediaKind.video : MediaKind.image,
        ),
      );
    } catch (_) {
      // The picker throws when permission was refused. Closing silently would
      // look like the tap did nothing, so say what is missing.
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).mediaPermission)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppDimens.gutter,
              end: AppDimens.gutter,
              bottom: 10,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.attachTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),

          // Said up front, not after a failed send: Instagram's accepted
          // formats are narrower than WhatsApp's, so a file that worked on one
          // thread can be refused on another. The server has the authoritative
          // list, so this warns rather than pre-validating.
          if (channel.isInstagram)
            AppBanner(message: l10n.mediaIgFormats, tone: BannerTone.warning),

          const Divider(),
          ActionSheetRow(
            label: l10n.attachPhoto,
            icon: Icons.photo_library_outlined,
            tint: AppColor.info,
            onTap: () => _pick(context, ImageSource.gallery, false),
          ),
          ActionSheetRow(
            label: l10n.attachCamera,
            icon: Icons.photo_camera_outlined,
            tint: AppColor.success,
            onTap: () => _pick(context, ImageSource.camera, false),
          ),
          ActionSheetRow(
            label: l10n.attachVideo,
            icon: Icons.videocam_outlined,
            tint: AppColor.warning,
            onTap: () => _pick(context, ImageSource.gallery, true),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.all(AppDimens.gutter),
            child: Text(
              l10n.attachDocNote,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
