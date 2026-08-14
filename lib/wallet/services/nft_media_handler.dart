import 'package:audio_service/audio_service.dart';
import 'package:audioplayers/audioplayers.dart';

/// Wraps the current NFT media playback so that Android shows a proper
/// media session (notification + lock screen controls) while a media NFT is
/// playing.
///
/// Audio NFTs are played through the internal [AudioPlayer] owned by this
/// handler. Video NFTs keep playing via `video_player` in the UI isolate; this
/// handler only exposes the media session (metadata, play/pause/seek state) and
/// forwards the system play/pause/seek commands back to the UI through the
/// [onVideoPlay] / [onVideoPause] / [onVideoSeek] hooks.
class NftMediaHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  /// True while a video NFT is being played through the UI.
  bool _videoSession = false;

  /// Callbacks the UI installs while a video NFT is active so that commands
  /// coming from the media session can reach the `video_player` controller.
  void Function()? onVideoPlay;
  void Function()? onVideoPause;
  void Function()? onVideoStop;
  void Function(Duration position)? onVideoSeek;

  NftMediaHandler() {
    _player.onPlayerStateChanged.listen((state) {
      final playing = state == PlayerState.playing;
      if (playing != playbackState.value.playing) {
        playbackState.add(playbackState.value.copyWith(playing: playing));
      }
    });
    _player.onPositionChanged.listen((position) {
      playbackState.add(playbackState.value.copyWith(updatePosition: position));
    });
    _player.onDurationChanged.listen((duration) {
      final item = mediaItem.value;
      if (item != null) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });
    _player.onPlayerComplete.listen((_) => stop());
  }

  /// Starts playing an audio NFT through this handler's player and publishes
  /// the media metadata to the media session.
  Future<void> playAudioNft({
    required String uri,
    required String title,
    String? artist,
    Uri? artUri,
  }) async {
    _videoSession = false;
    mediaItem.add(
      MediaItem(
        id: uri,
        title: title,
        artist: artist,
        artUri: artUri,
      ),
    );
    queue.add([
      MediaItem(id: uri, title: title, artist: artist, artUri: artUri),
    ]);
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.pause,
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 1],
        systemActions: const {MediaAction.seek},
        processingState: AudioProcessingState.loading,
        playing: false,
      ),
    );
    await _player.stop();
    await _player.play(UrlSource(uri));
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.ready,
        playing: true,
      ),
    );
  }

  /// Publishes a media session entry for a video NFT that is being played by
  /// the UI (via `video_player`). The actual playback stays in the UI; this
  /// handler only mirrors the metadata and state.
  void setVideoSession({
    required String uri,
    required String title,
    String? artist,
    Uri? artUri,
    Duration? duration,
    bool playing = true,
  }) {
    _videoSession = true;
    mediaItem.add(
      MediaItem(
        id: uri,
        title: title,
        artist: artist,
        artUri: artUri,
        duration: duration,
      ),
    );
    queue.add([
      MediaItem(
        id: uri,
        title: title,
        artist: artist,
        artUri: artUri,
        duration: duration,
      ),
    ]);
    _emitVideoState(playing: playing);
  }

  /// Updates the playing/position state published for the active video NFT.
  void updateVideoState({required bool playing, Duration position = Duration.zero}) {
    if (!_videoSession) return;
    _emitVideoState(playing: playing, position: position);
  }

  void _emitVideoState({required bool playing, Duration position = Duration.zero}) {
    playbackState.add(
      PlaybackState(
        controls: [
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 1],
        systemActions: const {MediaAction.seek},
        processingState: AudioProcessingState.ready,
        playing: playing,
        updatePosition: position,
      ),
    );
  }

  /// Removes the media session entry when the user leaves a video NFT screen.
  Future<void> clearVideoSession() async {
    _videoSession = false;
    onVideoPlay = null;
    onVideoPause = null;
    onVideoStop = null;
    onVideoSeek = null;
    await _clearSession();
  }

  Future<void> _clearSession() async {
    await _player.stop();
    mediaItem.add(null);
    queue.add(const []);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
        controls: const [],
      ),
    );
  }

  @override
  Future<void> play() async {
    if (_videoSession) {
      onVideoPlay?.call();
      _emitVideoState(playing: true);
    } else {
      await _player.resume();
      playbackState.add(playbackState.value.copyWith(playing: true));
    }
  }

  @override
  Future<void> pause() async {
    if (_videoSession) {
      onVideoPause?.call();
      _emitVideoState(playing: false);
    } else {
      await _player.pause();
      playbackState.add(playbackState.value.copyWith(playing: false));
    }
  }

  @override
  Future<void> stop() async {
    if (_videoSession) {
      onVideoStop?.call();
    }
    await _clearSession();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_videoSession) {
      onVideoSeek?.call(position);
      playbackState.add(playbackState.value.copyWith(updatePosition: position));
    } else {
      await _player.seek(position);
      playbackState.add(playbackState.value.copyWith(updatePosition: position));
    }
  }

  @override
  Future<void> onTaskRemoved() => stop();

  Future<void> dispose() => _player.dispose();
}
