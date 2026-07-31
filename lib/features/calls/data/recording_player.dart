import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/error/failure.dart';
import '../../../core/storage/secure_token_store.dart';

/// Plays a call recording from the authenticated recording endpoint.
///
/// `recordingUrl` used to be a plain asset URL that anything could open, so the
/// call-history screen handed it to the OS with `url_launcher`. It is now
/// `GET /api/v1/calls/{uid}/recording` behind a bearer token — the recordings
/// were world-readable and were moved off the public disk — and the system
/// browser has no token, so that path returns 401 and plays nothing.
///
/// The header has to travel with the request, which is what
/// [AudioSource.uri]'s `headers` is for. Handing the OS an authenticated URL
/// cannot be made to work.
class RecordingPlayer {
  RecordingPlayer(this._tokens);

  final SecureTokenStore _tokens;
  final AudioPlayer _player = AudioPlayer();

  Stream<PlayerState> get state => _player.playerStateStream;
  Stream<Duration> get position => _player.positionStream;
  Duration? get duration => _player.duration;
  bool get isPlaying => _player.playing;

  /// The uid currently loaded, so a list can show which row is playing.
  String? get loadedUid => _loadedUid;
  String? _loadedUid;

  /// Loads and starts [url]. Passing the same [callUid] again toggles pause.
  Future<void> toggle(String callUid, String url) async {
    if (_loadedUid == callUid) {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
      return;
    }

    final String? token = await _tokens.read();
    if (token == null || token.isEmpty) {
      // Reads as a session problem rather than a broken file, which is what it
      // is — the endpoint answers 401 without one.
      throw const AuthFailure();
    }

    try {
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(url),
          headers: <String, String>{'Authorization': 'Bearer $token'},
        ),
      );
      await _player.play();
      _loadedUid = callUid;
    } on PlayerException catch (e) {
      _loadedUid = null;
      // 404 is the deliberate answer for another workspace's call — a
      // distinguishable 403 would confirm the uid exists — so both codes mean
      // "not yours or not there" rather than "server broke".
      if (e.code == 401 || e.code == 403) throw const AuthFailure();
      if (e.code == 404) throw const NotFoundFailure();
      throw const ServerFailure('The recording could not be played.');
    } on PlayerInterruptedException {
      _loadedUid = null;
      throw const ServerFailure('The recording could not be played.');
    }
  }

  Future<void> stop() async {
    _loadedUid = null;
    await _player.stop();
  }

  void dispose() => _player.dispose();
}

/// One player for the app.
///
/// Deliberately not autoDispose and not per-screen: two players would let two
/// recordings talk over each other, and the platform audio session is a single
/// shared resource anyway.
final recordingPlayerProvider = Provider<RecordingPlayer>((Ref ref) {
  final RecordingPlayer p = RecordingPlayer(ref.watch(secureTokenStoreProvider));
  ref.onDispose(p.dispose);
  return p;
});
