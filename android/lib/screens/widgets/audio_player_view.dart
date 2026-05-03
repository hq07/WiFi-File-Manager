import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';
import '../../services/api_service.dart';
import '../../utils/format_utils.dart';
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

  const AudioPlayerView({
    super.key,
    required this.api,
    required this.filePath,
    required this.fileName,
    this.fileSize,
    required this.playlist,
    required this.sleepTimer,
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
        _controller!.play();
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

  void _onAudioProgress() {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (ctrl.value.position >= ctrl.value.duration &&
        ctrl.value.duration > Duration.zero) {
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
    _controller?.removeListener(_onAudioProgress);
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  // ---- Actions ----

  void _togglePlayPause() {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
    setState(() {});
  }

  void _setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    _controller?.setPlaybackSpeed(speed);
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
              : const [Color(0xFFf0eeff), Color(0xFFffffff)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(isDark),
            Expanded(child: _buildCenterContent(isDark)),
            _buildProgressSection(isDark),
            _buildMainControls(isDark),
            _buildBottomBar(isDark),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ---- Top bar ----

  Widget _buildTopBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back,
                color: isDark ? Colors.white70 : Colors.black54),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Center(
              child: Text('正在播放',
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
            ),
          ),
          IconButton(
            icon: Icon(Icons.info_outline,
                color: isDark ? Colors.white70 : Colors.black54),
            onPressed: _showInfoPanel,
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert,
                color: isDark ? Colors.white70 : Colors.black54),
            onSelected: (v) {},
            itemBuilder: (_) => [],
          ),
        ],
      ),
    );
  }

  // ---- Center content (album art) ----

  Widget _buildCenterContent(bool isDark) {
    final ext = widget.filePath.split('.').last.toUpperCase();
    final sizeStr = widget.fileSize != null ? formatSize(widget.fileSize!) : '';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Glow effect
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF6C63FF).withValues(alpha: 0.4),
                const Color(0xFF6C63FF).withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
        // Album art (positioned over the glow)
        Transform.translate(
          offset: const Offset(0, -180),
          child: Column(
            children: [
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF6C63FF),
                      Color(0xFF48c6ef),
                      Color(0xFFa855f7),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.35),
                      blurRadius: 30,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Music note icon
                    const Center(
                      child: Icon(Icons.music_note,
                          color: Colors.white, size: 72),
                    ),
                    // Reflection highlight on top half
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 110,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24)),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.15),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // File name
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  widget.fileName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              // Format info
              Text(
                [ext, if (sizeStr.isNotEmpty) sizeStr].join(' · '),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF6C63FF),
              inactiveTrackColor:
                  isDark ? Colors.white12 : Colors.black12,
              thumbColor: Colors.white,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 14),
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
            padding: const EdgeInsets.symmetric(horizontal: 12),
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

  // ---- Main controls ----

  Widget _buildMainControls(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Shuffle
          IconButton(
            icon: Icon(Icons.shuffle,
                size: 22,
                color: widget.playlist.shuffle
                    ? const Color(0xFF6C63FF)
                    : (isDark ? Colors.white30 : Colors.black26)),
            onPressed: () {
              widget.playlist.toggleShuffle();
            },
          ),
          const SizedBox(width: 8),
          // Previous
          IconButton(
            icon: Icon(Icons.skip_previous,
                size: 32,
                color: widget.playlist.hasPrevious
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? Colors.white24 : Colors.black12)),
            onPressed: widget.playlist.hasPrevious
                ? () {
                    _disposeController();
                    widget.playlist.previous();
                    _initAudio();
                  }
                : null,
          ),
          const SizedBox(width: 8),
          // Play/Pause
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6C63FF), Color(0xFF8b5cf6)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                    blurRadius: 16,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                _controller?.value.isPlaying == true
                    ? Icons.pause
                    : Icons.play_arrow,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Next
          IconButton(
            icon: Icon(Icons.skip_next,
                size: 32,
                color: widget.playlist.hasNext
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? Colors.white24 : Colors.black12)),
            onPressed: widget.playlist.hasNext
                ? () {
                    _disposeController();
                    widget.playlist.next();
                    _initAudio();
                  }
                : null,
          ),
          const SizedBox(width: 8),
          // Repeat
          _buildRepeatButton(isDark),
        ],
      ),
    );
  }

  Widget _buildRepeatButton(bool isDark) {
    final mode = widget.playlist.repeatMode;
    final isActive = mode != PlaylistRepeatMode.off;

    return GestureDetector(
      onTap: () => widget.playlist.toggleRepeat(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.repeat,
              size: 22,
              color: isActive
                  ? const Color(0xFF6C63FF)
                  : (isDark ? Colors.white30 : Colors.black26)),
          if (mode == PlaylistRepeatMode.one)
            const Text('1',
                style: TextStyle(
                    color: Color(0xFF6C63FF),
                    fontSize: 9,
                    fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ---- Bottom bar ----

  Widget _buildBottomBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Speed badge
          GestureDetector(
            onTap: _showSpeedSheet,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('${_playbackSpeed}x',
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 11)),
            ),
          ),
          const SizedBox(width: 12),
          // Sleep timer
          GestureDetector(
            onTap: _showSleepTimerSheet,
            child: widget.sleepTimer.isActive
                ? Text(
                    widget.sleepTimer.remainingFormatted,
                    style: const TextStyle(
                        color: Color(0xFF6C63FF),
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  )
                : Icon(Icons.alarm,
                    color: isDark ? Colors.white38 : Colors.black26,
                    size: 20),
          ),
          const Spacer(),
          // Volume icon
          Icon(
            _currentVolume <= 0
                ? Icons.volume_off
                : Icons.volume_up,
            color: isDark ? Colors.white38 : Colors.black26,
            size: 20,
          ),
          const SizedBox(width: 4),
          // Volume slider
          Expanded(
            flex: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFF6C63FF),
                inactiveTrackColor:
                    isDark ? Colors.white12 : Colors.black12,
                thumbColor: Colors.white,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 10),
                trackHeight: 2,
              ),
              child: Slider(
                value: _currentVolume.clamp(0.0, 1.0),
                onChanged: (v) {
                  _currentVolume = v;
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
