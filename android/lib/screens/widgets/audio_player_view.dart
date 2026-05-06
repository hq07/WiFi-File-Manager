import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';
import '../../services/api_service.dart';
import '../../utils/format_utils.dart';
import '../../services/history_service.dart';
import 'media_info_panel.dart';
import 'playlist_manager.dart';
import 'sleep_timer_manager.dart';

class AudioPlayerView extends StatefulWidget {
  final ApiService api;
  final String filePath;
  final String fileName;
  final int? fileSize;
  final PlaylistManager playlist;
  final SleepTimerManager sleepTimer;
  final HistoryService? historyService;
  final int initialPositionMs;
  final VoidCallback? onSwitchToVideo;

  const AudioPlayerView({
    super.key,
    required this.api,
    required this.filePath,
    required this.fileName,
    this.fileSize,
    required this.playlist,
    required this.sleepTimer,
    this.historyService,
    this.initialPositionMs = 0,
    this.onSwitchToVideo,
  });

  @override
  State<AudioPlayerView> createState() => _AudioPlayerViewState();
}

class _AudioPlayerViewState extends State<AudioPlayerView> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  double _playbackSpeed = 1.0;
  double _currentVolume = 0.5;
  bool _isMuted = false;
  double _volumeBeforeMute = 0.5;
  Timer? _positionUpdateTimer;

  static const List<double> _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  static const List<int> _sleepTimerOptions = [15, 30, 45, 60, 90];

  @override
  void initState() {
    super.initState();
    _initVolume();
    _initAudio();
  }

  @override
  void didUpdateWidget(covariant AudioPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _disposeController();
      _initAudio();
    }
  }

  Future<void> _initVolume() async {
    try {
      _currentVolume = await VolumeController.instance.getVolume();
    } catch (_) {}
  }

  Future<void> _initAudio() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final url = widget.api.getPreviewUrl(widget.filePath);
      _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await _controller!.initialize();
      _controller!.addListener(_onAudioProgress);
      _controller!.setPlaybackSpeed(_playbackSpeed);
      if (mounted) {
        setState(() => _isLoading = false);
        if (widget.initialPositionMs > 0) {
          await _controller!.seekTo(Duration(milliseconds: widget.initialPositionMs));
        }
        _controller!.play();
        _startHistoryTracking();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _startHistoryTracking() {
    final hs = widget.historyService;
    if (hs == null) return;
    final item = widget.playlist.currentItem;
    hs.addEntry(
      name: item['name'] ?? widget.fileName,
      path: widget.filePath,
      dirPath: widget.filePath.substring(0, widget.filePath.lastIndexOf('/')),
      size: item['size'] as int? ?? widget.fileSize ?? 0,
    );
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final ctrl = _controller;
      if (ctrl == null || !ctrl.value.isInitialized || !ctrl.value.isPlaying) return;
      hs.updatePosition(
        widget.filePath,
        ctrl.value.position.inMilliseconds,
        ctrl.value.duration.inMilliseconds,
      );
    });
  }

  void _saveCurrentPosition() {
    final hs = widget.historyService;
    final ctrl = _controller;
    if (hs == null || ctrl == null || !ctrl.value.isInitialized) return;
    hs.updatePosition(
      widget.filePath,
      ctrl.value.position.inMilliseconds,
      ctrl.value.duration.inMilliseconds,
    );
  }

  void _onAudioProgress() {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (ctrl.value.position >= ctrl.value.duration &&
        ctrl.value.duration > Duration.zero) {
      widget.historyService?.markCompleted(widget.filePath);
      if (widget.playlist.hasNext) {
        widget.playlist.next();
      } else {
        ctrl.seekTo(Duration.zero);
        ctrl.pause();
      }
    }
    if (mounted) setState(() {});
  }

  void _disposeController() {
    _saveCurrentPosition();
    _controller?.removeListener(_onAudioProgress);
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _positionUpdateTimer?.cancel();
    _disposeController();
    super.dispose();
  }

  // ---- Actions ----

  void _togglePlayPause() {
    final ctrl = _controller;
    if (ctrl == null) return;
    ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
    setState(() {});
  }

  void _setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    _controller?.setPlaybackSpeed(speed);
    setState(() {});
  }

  void _toggleMute() {
    if (_isMuted) {
      _currentVolume = _volumeBeforeMute;
      _isMuted = false;
    } else {
      _volumeBeforeMute = _currentVolume;
      _currentVolume = 0;
      _isMuted = true;
    }
    VolumeController.instance.setVolume(_currentVolume);
    setState(() {});
  }

  void _onSleepTimerExpired() {
    _controller?.pause();
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('定时关闭已触发，播放已暂停')),
      );
    }
  }

  void _showInfoPanel() {
    final item = widget.playlist.currentItem;
    MediaInfoPanel.show(
      context,
      fileName: item['name'] ?? widget.fileName,
      fileSize: item['size'] ?? widget.fileSize,
      duration: _controller != null && _controller!.value.isInitialized
          ? formatDuration(_controller!.value.duration)
          : null,
      format: (widget.filePath.split('.').last).toUpperCase(),
    );
  }

  // ---- Bottom sheets ----

  void _showSpeedSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('播放速度',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87)),
              ),
              ...ListTile.divideTiles(
                context: ctx,
                tiles: _speedOptions.map((speed) => ListTile(
                      title: Text('${speed}x',
                          style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87)),
                      trailing: _playbackSpeed == speed
                          ? const Icon(Icons.check, color: Color(0xFF6C63FF))
                          : null,
                      onTap: () {
                        _setPlaybackSpeed(speed);
                        Navigator.pop(ctx);
                      },
                    )),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showSleepTimerSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('定时关闭',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87)),
              ),
              ..._sleepTimerOptions.map((min) => ListTile(
                    title: Text('$min 分钟',
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87)),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.sleepTimer.start(
                        Duration(minutes: min),
                        _onSleepTimerExpired,
                      );
                      setState(() {});
                    },
                  )),
              if (widget.sleepTimer.isActive)
                ListTile(
                  title: const Text('取消定时', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.sleepTimer.cancel();
                    setState(() {});
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            const Text('音频加载失败', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                _disposeController();
                _initAudio();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF1a1040), Color(0xFF0f0c29)]
              : const [Color(0xFFF0EEFF), Color(0xFFFFFFFF)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(isDark),
            const Spacer(flex: 2),
            _buildAlbumArt(isDark),
            const Spacer(flex: 1),
            _buildProgressSection(isDark),
            _buildMainControls(isDark),
            _buildBottomBar(isDark),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ---- Top bar ----

  Widget _buildTopBar(bool isDark) {
    final item = widget.playlist.currentItem;
    final title = item['name'] ?? widget.fileName;
    // Remove extension for display
    final displayTitle = title.contains('.')
        ? title.substring(0, title.lastIndexOf('.'))
        : title;
    final ext = widget.filePath.split('.').last.toUpperCase();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Back
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(Icons.keyboard_arrow_down,
                color: isDark ? Colors.white70 : Colors.black54, size: 32),
          ),
          const SizedBox(width: 12),
          // Title + Artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayTitle,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(ext,
                    style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontSize: 13)),
              ],
            ),
          ),
          // Media switch
          if (widget.onSwitchToVideo != null)
            GestureDetector(
              onTap: widget.onSwitchToVideo,
              child: Icon(Icons.ondemand_video,
                  color: isDark ? Colors.white54 : Colors.black45, size: 22),
            ),
          const SizedBox(width: 12),
          // Info
          GestureDetector(
            onTap: _showInfoPanel,
            child: Icon(Icons.more_horiz,
                color: isDark ? Colors.white54 : Colors.black45, size: 22),
          ),
        ],
      ),
    );
  }

  // ---- Album art ----

  Widget _buildAlbumArt(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF6C63FF),
                Color(0xFF48C6EF),
                Color(0xFFA855F7),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                blurRadius: 40,
                spreadRadius: 4,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(Icons.music_note,
                    color: Colors.white.withValues(alpha: 0.85), size: 80),
              ),
              // Reflection
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 120,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Progress section ----

  Widget _buildProgressSection(bool isDark) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final position = ctrl.value.position;
    final duration = ctrl.value.duration;
    final maxMs = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final valueMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF6C63FF),
              inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              trackHeight: 3,
            ),
            child: Slider(
              value: valueMs,
              min: 0,
              max: maxMs,
              onChanged: (v) {
                ctrl.seekTo(Duration(milliseconds: v.round()));
                setState(() {});
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDuration(position),
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black45)),
                Text(formatDuration(duration),
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Main controls (prev / play / next) ----

  Widget _buildMainControls(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Previous
          _buildCircleButton(
            icon: Icons.skip_previous,
            size: 36,
            enabled: widget.playlist.hasPrevious,
            onTap: widget.playlist.hasPrevious
                ? () {
                    _disposeController();
                    widget.playlist.previous();
                    _initAudio();
                  }
                : null,
          ),
          const SizedBox(width: 28),
          // Play/Pause
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            child: Icon(
                _controller?.value.isPlaying == true
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
          const SizedBox(width: 28),
          // Next
          _buildCircleButton(
            icon: Icons.skip_next,
            size: 36,
            enabled: widget.playlist.hasNext,
            onTap: widget.playlist.hasNext
                ? () {
                    _disposeController();
                    widget.playlist.next();
                    _initAudio();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required double size,
    required bool enabled,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
        ),
        child: Icon(icon,
            color: enabled
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? Colors.white24 : Colors.black12),
            size: size),
      ),
    );
  }

  // ---- Bottom bar (play mode / timer / speed | volume) ----

  Widget _buildBottomBar(bool isDark) {
    final playMode = widget.playlist.playMode;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Play mode (sequential → shuffle → single repeat)
          GestureDetector(
            onTap: () => widget.playlist.cyclePlayMode(),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  playMode == PlayMode.shuffle ? Icons.shuffle : Icons.repeat,
                  size: 20,
                  color: playMode != PlayMode.sequential
                      ? const Color(0xFF6C63FF)
                      : (isDark ? Colors.white30 : Colors.black26),
                ),
                if (playMode == PlayMode.single)
                  const Text('1',
                      style: TextStyle(
                          color: Color(0xFF6C63FF),
                          fontSize: 8,
                          fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // Sleep timer
          GestureDetector(
            onTap: _showSleepTimerSheet,
            child: widget.sleepTimer.isActive
                ? Text(widget.sleepTimer.remainingFormatted,
                    style: const TextStyle(
                        color: Color(0xFF6C63FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600))
                : Icon(Icons.alarm,
                    color: isDark ? Colors.white30 : Colors.black26, size: 20),
          ),
          const SizedBox(width: 20),
          // Speed
          GestureDetector(
            onTap: _showSpeedSheet,
            child: Text('${_playbackSpeed}x',
                style: TextStyle(
                    color: _playbackSpeed != 1.0
                        ? const Color(0xFF6C63FF)
                        : (isDark ? Colors.white38 : Colors.black38),
                    fontSize: 12,
                    fontWeight:
                        _playbackSpeed != 1.0 ? FontWeight.w600 : FontWeight.normal)),
          ),
          const Spacer(),
          // Volume
          GestureDetector(
            onTap: _toggleMute,
            child: Icon(
              _isMuted || _currentVolume <= 0
                  ? Icons.volume_off
                  : _currentVolume < 0.5
                      ? Icons.volume_down
                      : Icons.volume_up,
              color: isDark ? Colors.white38 : Colors.black38,
              size: 20,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 100,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFF6C63FF),
                inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                trackHeight: 2,
              ),
              child: Slider(
                value: _currentVolume.clamp(0.0, 1.0),
                onChanged: (v) {
                  _currentVolume = v;
                  _isMuted = v == 0;
                  VolumeController.instance.setVolume(v);
                  setState(() {});
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
