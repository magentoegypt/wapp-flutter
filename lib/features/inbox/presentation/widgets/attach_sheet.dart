import 'dart:io';

import 'package:file_picker/file_picker.dart';
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

/// Meta's published ceiling for a document on WhatsApp.
///
/// Only used to stop an upload that cannot succeed. Erring generous on purpose:
/// a client cap set too low blocks a legitimate send, while one set too high
/// merely wastes an upload the server then refuses — and Instagram's own limit
/// is lower than this, which the server enforces.
const int _maxDocumentBytes = 100 * 1024 * 1024;

/// Attachment picker.
///
/// Images, video and documents. The document row was absent while the app had
/// no file-picker dependency; the contacts import added one, so it exists now.
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

  Future<void> _pickDocument(BuildContext context) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: channel.documentExtensions,
      // The upload streams from the path; pulling 100 MB into memory to hand it
      // straight back to a file read would be the one way to make this OOM.
      withData: false,
    );
    final PlatformFile? file = picked?.files.singleOrNull;
    if (file == null || file.path == null) return; // cancelled

    if (!channel.acceptsDocument(file.name)) {
      // Some pickers ignore `allowedExtensions` — the same reason the contacts
      // import re-checks. On Instagram this is the difference between a refusal
      // now and one after a full upload.
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            channel.isInstagram ? l10n.attachDocIgOnlyPdf : l10n.attachDocType,
          ),
        ),
      );
      return;
    }

    // `file.size` is 0 on some platforms when withData is false, so the file
    // itself is the source of truth; a zero there means "unknown", not empty.
    int size = file.size;
    if (size <= 0) {
      try {
        size = await File(file.path!).length();
      } catch (_) {
        size = 0;
      }
    }
    if (size > _maxDocumentBytes) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.attachDocTooLarge)),
      );
      return;
    }

    navigator.pop(
      PickedMedia(
        path: file.path!,
        fileName: file.name,
        kind: MediaKind.document,
      ),
    );
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
          ActionSheetRow(
            // The label names the accepted set, so the narrower Instagram rule
            // is visible before the picker opens rather than after it refuses.
            label: channel.isInstagram
                ? l10n.attachDocumentPdf
                : l10n.attachDocument,
            icon: Icons.description_outlined,
            tint: AppColor.brandDeep,
            onTap: () => _pickDocument(context),
          ),
        ],
      ),
    );
  }
}
