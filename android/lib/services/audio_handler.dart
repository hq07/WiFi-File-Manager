import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'api_service.dart';
import 'playback_state.dart';

class AudioPlayerService extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  ApiService? _api;
  List<Map<String, dynamic>> _playlistItems = [];
  int _currentIndex = 0;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;

  AudioPlayer get player => _player;
  int get currentIndex => _currentIndex;
  List<Map<String, dynamic>> get playlistItems => _playlistItems;
  ApiService? get api => _api;

  AudioPlayerService._();

  static Future<AudioPlayerService> create() async {
    final service = AudioPlayerService._();
    await service._init();
    return service;
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _positionSub = _player.positionStream.listen((pos) {
      playbackState.add(playbackState.value.copyWith(
        updatePosition: pos,
      ));
      playbackStateNotifier.setPosition(pos);
    });

    _durationSub = _player.durationStream.listen((dur) {
      if (dur != null) {
        playbackStateNotifier.setDuration(dur);
      }
    });

    _stateSub = _player.playerStateStream.listen((state) {
      final playing = state.playing;
      final processingState = _mapProcessingState(state.processingState);

      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: processingState,
        playing: playing,
      ));

      playbackStateNotifier.setPlaying(playing);

      if (state.processingState == ProcessingState.completed) {
        _onTrackCompleted();
      }
    });

    await AudioService.init(
      builder: () => this,
      config: const AudioServiceConfig(
        androidStopForegroundOnPause: true,
        androidNotificationChannelId: 'com.wififilemanager.audio',
        androidNotificationChannelName: '音乐播放',
        androidNotificationOngoing: false,
      ),
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  Future<void> loadPlaylist(
    List<Map<String, dynamic>> items, {
    int startIndex = 0,
    required ApiService api,
  }) async {
    _playlistItems = items;
    _api = api;
    _currentIndex = startIndex.clamp(0, items.length - 1);
    await _loadCurrentTrack();
  }

  Future<void> _loadCurrentTrack() async {
    if (_playlistItems.isEmpty || _api == null) return;
    final item = _playlistItems[_currentIndex];
    final url = _api!.getPreviewUrl(item['path']);
    try {
      await _player.setUrl(url);
      _updateMediaItem(item);
      _syncPlaybackStateNotifier();
      await _player.play();
    } catch (_) {}
  }

  void _updateMediaItem(Map<String, dynamic> item) {
    mediaItem.add(MediaItem(
      id: item['path'] ?? '',
      title: item['name'] ?? '未知',
      artist: 'WiFi File Manager',
      duration: _player.duration,
    ));
  }

  void _syncPlaybackStateNotifier() {
    if (_playlistItems.isEmpty) return;
    final item = _playlistItems[_currentIndex];
    playbackStateNotifier.updatePlaying(
      filePath: item['path'] ?? '',
      fileName: item['name'] ?? '',
      fileSize: item['size'],
      directoryFiles: _playlistItems,
      isPlaying: _player.playing,
    );
  }

  void _onTrackCompleted() {
    // PlaylistManager handles repeat/shuffle logic externally,
    // so we just notify — the MediaPlayerScreen listener calls skipToIndex.
    // If no external listener, auto-advance:
    if (_currentIndex < _playlistItems.length - 1) {
      skipToNext();
    } else {
      playbackStateNotifier.setPlaying(false);
    }
  }

  Future<void> skipToIndex(int index) async {
    if (index < 0 || index >= _playlistItems.length) return;
    _currentIndex = index;
    await _loadCurrentTrack();
  }

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    playbackStateNotifier.clear();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (_currentIndex < _playlistItems.length - 1) {
      await skipToIndex(_currentIndex + 1);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_currentIndex > 0) {
      await skipToIndex(_currentIndex - 1);
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  Future<void> dispose() async {
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _stateSub?.cancel();
    await _player.dispose();
  }
}

late AudioPlayerService audioPlayerService;
