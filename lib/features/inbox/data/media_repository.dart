import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/envelope.dart';

/// What kind of attachment is being sent.
///
/// `document` is spelled `file` on the wire — the server normalises it back to
/// `document` on the way out, and `media.sourceKind` keeps the raw value. The
/// asymmetry is easy to trip over, so it is encoded here rather than at the
/// call site.
enum MediaKind { image, video, audio, document }

extension MediaKindX on MediaKind {
  String get wire => this == MediaKind.document ? 'file' : name;
}

/// Sending an attachment.
///
/// Two steps, always: upload the bytes, then send the returned filename.
///
/// WhatsApp would also accept a `mediaUrl`, but Instagram answers 422 for it —
/// it is upload-only. Rather than branch on channel, this always uploads,
/// because the upload path is the one that works on both and a branch here
/// would be a second code path exercised only by 2 of 36 contacts.
abstract interface class MediaRepository {
  /// Returns the server's `uploadedFileName`, which is what the send takes.
  Future<String> upload({
    required String path,
    required String fileName,
    void Function(int sent, int total)? onProgress,
  });

  Future<void> send({
    required String contactUid,
    required String uploadedFileName,
    required MediaKind kind,
    String? caption,
  });
}

class MediaRepositoryImpl implements MediaRepository {
  const MediaRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<String> upload({
    required String path,
    required String fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final FormData form = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(path, filename: fileName),
    });

    // ApiClient.post forwards `body` straight to dio, which recognises FormData
    // and sets the multipart boundary itself — no special client method needed.
    final dynamic body = await _api.post(
      '/media/upload',
      body: form,
      onSendProgress: onProgress,
      timeout: const Duration(minutes: 5),
    );

    final Map<String, dynamic> m = envelopeRecord(body, 'media');
    final String name =
        '${m['uploadedFileName'] ?? m['fileName'] ?? m['file'] ?? ''}';
    if (name.isEmpty) {
      // A 200 with no filename would otherwise send an empty attachment, which
      // the customer receives as a broken bubble rather than as an error.
      throw const ServerFailure('The upload did not return a file name.');
    }
    return name;
  }

  @override
  Future<void> send({
    required String contactUid,
    required String uploadedFileName,
    required MediaKind kind,
    String? caption,
  }) async {
    await _api.post(
      '/conversations/$contactUid/messages/media',
      body: <String, dynamic>{
        // NOT mediaUrl. Instagram refuses that with a 422 and WhatsApp accepts
        // both, so the uploaded name is the only field that serves both.
        'uploadedFileName': uploadedFileName,
        'type': kind.wire,
        if (caption != null && caption.trim().isNotEmpty)
          'caption': caption.trim(),
      },
    );
  }
}

final mediaRepositoryProvider = Provider<MediaRepository>(
  (Ref ref) => MediaRepositoryImpl(ref.watch(apiClientProvider)),
);
