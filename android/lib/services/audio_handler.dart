import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'api_service.dart';
import 'playback_state.dart';
import 'history_service.dart';

class AudioPlayerService extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  ApiService? _api;
  HistoryService? _historyService;
  Timer? _historyTimer;
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

  void setHistoryService(HistoryService hs) {
    _historyService = hs;
    _historyTimer?.cancel();
    _historyTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_historyService == null || !_player.playing) return;
      if (_playlistItems.isEmpty || _api == null) return;
      final dur = _player.duration;
      if (dur == null || dur == Duration.zero) return;
      _historyService!.updatePosition(
        _playlistItems[_currentIndex]['path'],
        _player.position.inMilliseconds,
        dur.inMilliseconds,
      );
    });
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
    final newIndex = startIndex.clamp(0, items.length - 1);

    // 跳过重复加载：如果播放列表和当前曲目相同，不重新加载
    if (_playlistItems.isNotEmpty &&
        _currentIndex == newIndex &&
        _playlistItems.length == items.length &&
        _playlistItems[_currentIndex]['path'] == items[newIndex]['path']) {
      _playlistItems = items;
      _api = api;
      _syncPlaybackStateNotifier();
      return;
    }

    _playlistItems = items;
    _api = api;
    _currentIndex = newIndex;
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
    final path = item['path'] ?? '';
    playbackStateNotifier.updatePlaying(
      filePath: path,
      fileName: item['name'] ?? '',
      fileSize: item['size'],
      directoryFiles: _playlistItems,
      isPlaying: _player.playing,
    );
    // 确保历史记录条目存在，以便定时器能更新进度
    if (_historyService != null && path.isNotEmpty) {
      _historyService!.addEntry(
        name: item['name'] ?? '',
        path: path,
        dirPath: path.substring(0, path.lastIndexOf('/')),
        size: item['size'] as int? ?? 0,
      );
    }
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
