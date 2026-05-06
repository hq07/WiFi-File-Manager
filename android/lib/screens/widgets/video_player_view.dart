import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import '../../services/api_service.dart';
import '../../utils/format_utils.dart';
import '../../services/history_service.dart';
import 'gesture_handler.dart';
import 'media_info_panel.dart';
import 'playlist_manager.dart';
import 'sleep_timer_manager.dart';

enum VideoFitMode { fit, stretch, original }

class VideoPlayerView extends StatefulWidget {
  final ApiService api;
  final String filePath;
  final String fileName;
  final int? fileSize;
  final PlaylistManager playlist;
  final SleepTimerManager sleepTimer;
  final VoidCallback onToggleFullscreen;
  final bool isFullscreen;
  final HistoryService? historyService;

  const VideoPlayerView({
    super.key,
    required this.api,
    required this.filePath,
    required this.fileName,
    this.fileSize,
    required this.playlist,
    required this.sleepTimer,
    required this.onToggleFullscreen,
    required this.isFullscreen,
    this.historyService,
  });

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _showControls = true;
  bool _locked = false;
  bool _showBrightnessOverlay = false;
  bool _showVolumeOverlay = false;
  double _currentBrightness = 0;
  double _currentVolume = 0;
  Timer? _hideControlsTimer;
  Timer? _hideOverlayTimer;
  Timer? _positionUpdateTimer;

  // Gesture overlay state
  OverlayEntry? _gestureOverlay;
  AnimationController? _gestureAnimController;

  // Speed options
  static const List<double> _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  double _playbackSpeed = 1.0;

  // Video fit mode
  VideoFitMode _fitMode = VideoFitMode.fit;

  // Sleep timer options in minutes
  static const List<int> _sleepTimerOptions = [15, 30, 45, 60, 90];

  @override
  void initState() {
    super.initState();
    _gestureAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _initVideo();
    _initVolume();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _disposeController();
      _initVideo();
    }
  }

  Future<void> _initVolume() async {
    try {
      _currentVolume = await VolumeController.instance.getVolume();
    } catch (_) {}
  }

  Future<void> _initVideo() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final url = widget.api.getPreviewUrl(widget.filePath);
      _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await _controller!.initialize();
      _controller!.addListener(_onVideoProgress);
      _controller!.setPlaybackSpeed(_playbackSpeed);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _controller!.play();
        _startHideControlsTimer();
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

  void _onVideoProgress() {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (ctrl.value.position >= ctrl.value.duration &&
        ctrl.value.duration > Duration.zero) {
      widget.historyService?.markCompleted(widget.filePath);
      // Auto-advance to next playlist item
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
    _controller?.removeListener(_onVideoProgress);
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _saveCurrentPosition();
    _positionUpdateTimer?.cancel();
    _disposeController();
    _hideControlsTimer?.cancel();
    _hideOverlayTimer?.cancel();
    _gestureAnimController?.dispose();
    _removeGestureOverlay();
    super.dispose();
  }

  // ---- Controls visibility ----

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_controller?.value.isPlaying == true) {
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _controller?.value.isPlaying == true) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  // ---- Gesture callbacks ----

  void _onDoubleTap(GestureZone zone) {
    switch (zone) {
      case GestureZone.left:
        _seekRelative(-10);
        _showGestureOverlay(Icons.replay_10, '-10s');
        break;
      case GestureZone.center:
        _togglePlayPause();
        _showGestureOverlay(
          _controller?.value.isPlaying == true
              ? Icons.play_arrow
              : Icons.pause,
          _controller?.value.isPlaying == true ? '▶' : '⏸',
        );
        break;
      case GestureZone.right:
        _seekRelative(10);
        _showGestureOverlay(Icons.forward_10, '+10s');
        break;
    }
  }

  void _seekRelative(int seconds) {
    final ctrl = _controller;
    if (ctrl == null) return;
    final newPos = ctrl.value.position + Duration(seconds: seconds);
    final clamped = newPos < Duration.zero
        ? Duration.zero
        : (newPos > ctrl.value.duration ? ctrl.value.duration : newPos);
    ctrl.seekTo(clamped);
    _startHideControlsTimer();
  }

  void _togglePlayPause() {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
    setState(() {});
    _startHideControlsTimer();
  }

  void _onHorizontalDrag(double delta) {
    final ctrl = _controller;
    if (ctrl == null) return;
    // 1% of screen width = ~2 seconds
    final screenWidth = MediaQuery.of(context).size.width;
    final secondsDelta = (delta / screenWidth) * 100 * 2;
    final newPos =
        ctrl.value.position + Duration(milliseconds: (secondsDelta * 1000).round());
    final clamped = newPos < Duration.zero
        ? Duration.zero
        : (newPos > ctrl.value.duration ? ctrl.value.duration : newPos);
    ctrl.seekTo(clamped);
    setState(() {});
  }

  void _onVerticalDrag(VerticalZone zone, double delta) {
    final screenHeight = MediaQuery.of(context).size.height;
    final change = -delta / screenHeight;
    if (zone == VerticalZone.leftHalf) {
      _adjustBrightness(change);
    } else {
      _adjustVolume(change);
    }
  }

  Future<void> _adjustBrightness(double change) async {
    try {
      _currentBrightness =
          (_currentBrightness + change).clamp(0.0, 1.0);
      await ScreenBrightness.instance
          .setApplicationScreenBrightness(_currentBrightness);
      setState(() {
        _showBrightnessOverlay = true;
        _showVolumeOverlay = false;
      });
      _resetOverlayTimer();
    } catch (_) {}
  }

  Future<void> _adjustVolume(double change) async {
    try {
      _currentVolume = (_currentVolume + change).clamp(0.0, 1.0);
      VolumeController.instance.setVolume(_currentVolume);
      setState(() {
        _showVolumeOverlay = true;
        _showBrightnessOverlay = false;
      });
      _resetOverlayTimer();
    } catch (_) {}
  }

  void _resetOverlayTimer() {
    _hideOverlayTimer?.cancel();
    _hideOverlayTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showBrightnessOverlay = false;
          _showVolumeOverlay = false;
        });
      }
    });
  }

  void _onVerticalDragStart() {
    // Sync current brightness value
    try {
      ScreenBrightness.instance.application.then((v) {
        _currentBrightness = v;
      });
    } catch (_) {}
    try {
      VolumeController.instance.getVolume().then((v) {
        _currentVolume = v;
      });
    } catch (_) {}
  }

  void _onVerticalDragEnd() {
    _hideOverlayTimer?.cancel();
    _hideOverlayTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _showBrightnessOverlay = false;
          _showVolumeOverlay = false;
        });
      }
    });
  }

  // ---- Gesture overlay animation ----

  void _showGestureOverlay(IconData icon, String text) {
    _removeGestureOverlay();
    _gestureAnimController!.reset();
    _gestureAnimController!.forward();

    _gestureOverlay = OverlayEntry(
      builder: (context) => _GestureAnimationOverlay(
        icon: icon,
        text: text,
        animation: _gestureAnimController!,
        onDismiss: _removeGestureOverlay,
      ),
    );
    Overlay.of(context).insert(_gestureOverlay!);

    Future.delayed(const Duration(milliseconds: 800), _removeGestureOverlay);
  }

  void _removeGestureOverlay() {
    _gestureOverlay?.remove();
    _gestureOverlay = null;
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

  void _setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    _controller?.setPlaybackSpeed(speed);
    setState(() {});
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

  // ---- Video fit mode ----

  double get _displayAspectRatio {
    // Use server-provided DAR (accounts for SAR), fall back to pixel ratio
    final dar = widget.playlist.currentItem['display_aspect_ratio'];
    if (dar is num && dar > 0) return dar.toDouble();
    return _controller!.value.aspectRatio;
  }

  Widget _buildVideoSurface() {
    final ctrl = _controller!;
    switch (_fitMode) {
      case VideoFitMode.fit:
        return Center(
          child: AspectRatio(
            aspectRatio: _displayAspectRatio,
            child: VideoPlayer(ctrl),
          ),
        );
      case VideoFitMode.stretch:
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: ctrl.value.size.width,
              height: ctrl.value.size.height,
              child: VideoPlayer(ctrl),
            ),
          ),
        );
      case VideoFitMode.original:
        return Center(
          child: SizedBox(
            width: ctrl.value.size.width,
            height: ctrl.value.size.height,
            child: VideoPlayer(ctrl),
          ),
        );
    }
  }

  static const Map<VideoFitMode, String> _fitModeLabels = {
    VideoFitMode.fit: '适配',
    VideoFitMode.stretch: '拉伸',
    VideoFitMode.original: '100%',
  };

  static const Map<VideoFitMode, IconData> _fitModeIcons = {
    VideoFitMode.fit: Icons.fit_screen,
    VideoFitMode.stretch: Icons.aspect_ratio,
    VideoFitMode.original: Icons.photo_size_select_actual,
  };

  void _showFitModeSheet() {
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
                child: Text('画面适应',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87)),
              ),
              ...VideoFitMode.values.map((mode) => ListTile(
                    leading: Icon(
                      _fitModeIcons[mode],
                      color: _fitMode == mode
                          ? const Color(0xFF6C63FF)
                          : (isDark ? Colors.white70 : Colors.black54),
                    ),
                    title: Text(_fitModeLabels[mode]!,
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87)),
                    trailing: _fitMode == mode
                        ? const Icon(Icons.check, color: Color(0xFF6C63FF))
                        : null,
                    onTap: () {
                      setState(() => _fitMode = mode);
                      Navigator.pop(ctx);
                    },
                  )),
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
            const Text('视频加载失败', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                _disposeController();
                _initVideo();
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

    return Stack(
      children: [
        // Video surface
        Positioned.fill(
          child: GestureDetector(
            onTap: _toggleControls,
            child: Container(
              color: Colors.black,
              child: _buildVideoSurface(),
            ),
          ),
        ),
        // Gesture handler overlay
        Positioned.fill(
          child: GestureHandler(
            onSingleTap: _locked ? null : _toggleControls,
            onDoubleTap: _locked ? null : _onDoubleTap,
            onHorizontalDrag: _locked ? null : _onHorizontalDrag,
            onVerticalDrag: _locked ? null : _onVerticalDrag,
            onVerticalDragStart: _locked ? null : _onVerticalDragStart,
            onVerticalDragEnd: _locked ? null : _onVerticalDragEnd,
            child: const SizedBox.expand(),
          ),
        ),
        // Top bar
        if (_showControls) _buildTopBar(isDark),
        // Lock button
        if (_locked || _showControls) _buildLockButton(),
        // Bottom controls
        if (_showControls) _buildBottomToolbar(isDark),
        // Brightness overlay
        if (_showBrightnessOverlay) _buildSideOverlay(
          Icons.brightness_6,
          '${(_currentBrightness * 100).round()}%',
          Alignment.centerLeft,
        ),
        // Volume overlay
        if (_showVolumeOverlay) _buildSideOverlay(
          _currentVolume <= 0 ? Icons.volume_off : Icons.volume_up,
          '${(_currentVolume * 100).round()}%',
          Alignment.centerRight,
        ),
      ],
    );
  }

  // ---- Top bar ----

  Widget _buildTopBar(bool isDark) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 4,
          left: 8,
          right: 8,
          bottom: 8,
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                widget.playlist.currentItem['name'] ?? widget.fileName,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.white),
              onPressed: _showInfoPanel,
            ),
          ],
        ),
      ),
    );
  }

  // ---- Center controls (large play/pause/prev/next) ----

  Widget _buildCenterControls() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return const SizedBox.shrink();

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Previous
          _buildCircleButton(
            icon: Icons.skip_previous,
            size: 40,
            enabled: widget.playlist.hasPrevious,
            onTap: widget.playlist.hasPrevious
                ? () {
                    _disposeController();
                    widget.playlist.previous();
                    _initVideo();
                  }
                : null,
          ),
          const SizedBox(width: 32),
          // Play/Pause — large
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: Icon(
                ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          const SizedBox(width: 32),
          // Next
          _buildCircleButton(
            icon: Icons.skip_next,
            size: 40,
            enabled: widget.playlist.hasNext,
            onTap: widget.playlist.hasNext
                ? () {
                    _disposeController();
                    widget.playlist.next();
                    _initVideo();
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black38,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: enabled ? Colors.white : Colors.white30, size: size),
      ),
    );
  }

  // ---- Progress area (progress bar + time + lock) ----

  Widget _buildProgressArea(bool isDark) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return const SizedBox.shrink();

    final position = ctrl.value.position;
    final duration = ctrl.value.duration;

    return Positioned(
      left: 0,
      right: 0,
      bottom: _locked ? MediaQuery.of(context).padding.bottom : 48 + MediaQuery.of(context).padding.bottom,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress bar
            VideoProgressIndicator(
              ctrl,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Color(0xFF6C63FF),
                bufferedColor: Colors.white30,
                backgroundColor: Colors.white24,
              ),
            ),
            const SizedBox(height: 4),
            // Time + lock
            Row(
              children: [
                Text(
                  formatDuration(position),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text(
                  formatDuration(duration),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- Bottom toolbar (fit, speed, timer, fullscreen, playlist) ----

  Widget _buildBottomToolbar(bool isDark) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        color: Colors.black54,
        padding: EdgeInsets.only(
          left: 8,
          right: 8,
          bottom: MediaQuery.of(context).padding.bottom,
          top: 4,
        ),
        child: Row(
          children: [
            // Fit mode
            _buildToolbarButton(
              label: _fitModeLabels[_fitMode]!,
              icon: _fitModeIcons[_fitMode],
              isActive: _fitMode != VideoFitMode.fit,
              onTap: _showFitModeSheet,
            ),
            // Speed
            _buildToolbarButton(
              label: '${_playbackSpeed}x',
              isActive: _playbackSpeed != 1.0,
              onTap: _showSpeedSheet,
            ),
            // Sleep timer
            _buildToolbarButton(
              label: widget.sleepTimer.isActive ? widget.sleepTimer.remainingFormatted : null,
              icon: Icons.alarm,
              isActive: widget.sleepTimer.isActive,
              onTap: _showSleepTimerSheet,
            ),
            const Spacer(),
            // Playlist
            if (widget.playlist.items.length > 1)
              _buildToolbarButton(
                label: '${widget.playlist.currentIndex + 1}/${widget.playlist.items.length}',
                icon: Icons.playlist_play,
                onTap: _showPlaylistSheet,
              ),
            // Fullscreen
            _buildToolbarButton(
              icon: widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              onTap: widget.onToggleFullscreen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarButton({
    String? label,
    IconData? icon,
    bool isActive = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon, color: isActive ? const Color(0xFF6C63FF) : Colors.white70, size: 18),
            if (label != null) ...[
              if (icon != null) const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? const Color(0xFF6C63FF) : Colors.white70,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---- Playlist sheet ----

  void _showPlaylistSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.8,
          minChildSize: 0.3,
          expand: false,
          builder: (_, scrollCtrl) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text('播放列表',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87)),
                      const Spacer(),
                      Text('${widget.playlist.items.length} 个文件',
                          style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black45,
                              fontSize: 13)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    itemCount: widget.playlist.items.length,
                    itemBuilder: (_, i) {
                      final item = widget.playlist.items[i];
                      final isCurrent = i == widget.playlist.currentIndex;
                      return ListTile(
                        leading: Icon(
                          isCurrent ? Icons.play_circle_filled : Icons.play_circle_outline,
                          color: isCurrent ? const Color(0xFF6C63FF) : Colors.grey,
                        ),
                        title: Text(
                          item['name'] ?? '',
                          style: TextStyle(
                            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                            color: isCurrent
                                ? const Color(0xFF6C63FF)
                                : (isDark ? Colors.white : Colors.black87),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _disposeController();
                          widget.playlist.jumpTo(i);
                          _initVideo();
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---- Lock button ----

  Widget _buildLockButton() {
    return Positioned(
      left: 12,
      bottom: 48 + MediaQuery.of(context).padding.bottom + 16,
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (_locked) {
              _locked = false;
              _showControls = true;
              _startHideControlsTimer();
            } else {
              _locked = true;
              _showControls = false;
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            _locked ? Icons.lock : Icons.lock_open,
            color: Colors.white70,
            size: 20,
          ),
        ),
      ),
    );
  }

  void _resetHideControlsTimer() => _startHideControlsTimer();

  // ---- Side overlay (brightness / volume) ----

  Widget _buildSideOverlay(IconData icon, String label, Alignment alignment) {
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.3,
      left: alignment == Alignment.centerLeft ? 16 : null,
      right: alignment == Alignment.centerRight ? 16 : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ---- Gesture animation overlay ----

class _GestureAnimationOverlay extends StatelessWidget {
  final IconData icon;
  final String text;
  final Animation<double> animation;
  final VoidCallback onDismiss;

  const _GestureAnimationOverlay({
    required this.icon,
    required this.text,
    required this.animation,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOut),
      ),
      child: Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 28),
              Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
