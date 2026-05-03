# Media Player Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the Flutter APK's playback interface into a polished, feature-rich media player supporting video, audio, image, and text/code files with gesture controls, playlist, sleep timer, and adaptive theme.

**Architecture:** Unified `MediaPlayerScreen` shell handles fullscreen, gestures, theme, and sleep timer. Type-specific content views (`VideoPlayerView`, `AudioPlayerView`, `ImageGalleryView`, `TextCodeView`) are composed inside it. Shared managers (`PlaylistManager`, `SleepTimerManager`) and utilities (`format_utils.dart`) reduce duplication.

**Tech Stack:** Flutter/Dart, video_player, photo_view, flutter_highlight, wakelock_plus, screen_brightness, volume_controller

---

### Task 1: Add Dependencies & Extract Shared Utilities

**Files:**
- Modify: `android/pubspec.yaml`
- Create: `android/lib/utils/format_utils.dart`

- [ ] **Step 1: Add new dependencies to pubspec.yaml**

Add these under `dependencies:` in `android/pubspec.yaml`:

```yaml
  highlight: ^0.7.0
  flutter_highlight: ^0.7.0
  wakelock_plus: ^1.2.1
  screen_brightness: ^2.0.0
  volume_controller: ^1.0.0
  collection: ^1.19.0
```

- [ ] **Step 2: Run flutter pub get**

Run: `cd android && flutter pub get`
Expected: All dependencies resolve successfully.

- [ ] **Step 3: Create format_utils.dart**

Create `android/lib/utils/format_utils.dart`:

```dart
String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String getLanguageName(String ext) {
  const map = {
    'py': 'Python', 'js': 'JavaScript', 'ts': 'TypeScript',
    'json': 'JSON', 'html': 'HTML', 'htm': 'HTML', 'css': 'CSS',
    'md': 'Markdown', 'yaml': 'YAML', 'yml': 'YAML', 'go': 'Go',
    'rs': 'Rust', 'java': 'Java', 'c': 'C', 'cpp': 'C++', 'h': 'C/C++ Header',
    'sh': 'Shell', 'bash': 'Shell', 'sql': 'SQL', 'xml': 'XML', 'toml': 'TOML',
    'txt': 'Plain Text', 'csv': 'CSV', 'log': 'Log',
  };
  return map[ext] ?? ext.toUpperCase();
}

String getHighlightLanguage(String ext) {
  const map = {
    'py': 'python', 'js': 'javascript', 'ts': 'typescript',
    'json': 'json', 'html': 'html', 'htm': 'html', 'css': 'css',
    'md': 'markdown', 'yaml': 'yaml', 'yml': 'yaml', 'go': 'go',
    'rs': 'rust', 'java': 'java', 'c': 'c', 'cpp': 'cpp', 'h': 'c',
    'sh': 'bash', 'bash': 'bash', 'sql': 'sql', 'xml': 'xml', 'toml': 'ini',
  };
  return map[ext] ?? '';
}

bool isCodeFile(String ext) {
  return ['py', 'js', 'ts', 'json', 'html', 'htm', 'css', 'go', 'rs',
          'java', 'c', 'cpp', 'h', 'sh', 'bash', 'sql', 'xml', 'toml',
          'yaml', 'yml'].contains(ext);
}
```

- [ ] **Step 4: Update FileListScreen and HomeScreen to use format_utils**

Replace the duplicated `_formatSize` method in both `file_list_screen.dart` and `home_screen.dart` with:

```dart
import '../utils/format_utils.dart';
```

Then delete the local `_formatSize` methods and replace calls with `formatSize(...)`.

- [ ] **Step 5: Commit**

```bash
cd /Users/hq/python/code/WiFi-File-Manager
git add android/pubspec.yaml android/pubspec.lock android/lib/utils/format_utils.dart android/lib/screens/file_list_screen.dart android/lib/screens/home_screen.dart
git commit -m "feat: add media player deps and extract shared format utils"
```

---

### Task 2: SleepTimerManager & PlaylistManager

**Files:**
- Create: `android/lib/screens/widgets/playlist_manager.dart`
- Create: `android/lib/screens/widgets/sleep_timer_manager.dart`

- [ ] **Step 1: Create PlaylistManager**

Create `android/lib/screens/widgets/playlist_manager.dart`:

```dart
import 'package:flutter/foundation.dart';

enum PlaylistRepeatMode { off, all, one }

class PlaylistManager extends ChangeNotifier {
  List<Map<String, dynamic>> _items = [];
  int _currentIndex = 0;
  bool _shuffle = false;
  PlaylistRepeatMode _repeatMode = PlaylistRepeatMode.off;
  List<int> _shuffleOrder = [];

  List<Map<String, dynamic>> get items => _items;
  int get currentIndex => _currentIndex;
  bool get shuffle => _shuffle;
  PlaylistRepeatMode get repeatMode => _repeatMode;

  Map<String, dynamic> get currentItem =>
      _items.isNotEmpty ? _items[_currentIndex] : {};

  bool get hasNext {
    if (_repeatMode == PlaylistRepeatMode.all || _repeatMode == PlaylistRepeatMode.one) return true;
    return _currentIndex < _items.length - 1;
  }

  bool get hasPrevious {
    if (_repeatMode == PlaylistRepeatMode.all) return true;
    return _currentIndex > 0;
  }

  void setItems(List<Map<String, dynamic>> items, {int startIndex = 0}) {
    _items = List.from(items);
    _currentIndex = startIndex.clamp(0, items.length - 1);
    _generateShuffleOrder();
    notifyListeners();
  }

  void _generateShuffleOrder() {
    _shuffleOrder = List.generate(_items.length, (i) => i);
    _shuffleOrder.shuffle();
  }

  void next() {
    if (_items.isEmpty) return;
    if (_repeatMode == PlaylistRepeatMode.one) {
      notifyListeners();
      return;
    }
    if (_shuffle) {
      final idx = _shuffleOrder.indexOf(_currentIndex);
      final nextIdx = (idx + 1) % _shuffleOrder.length;
      _currentIndex = _shuffleOrder[nextIdx];
    } else {
      _currentIndex++;
      if (_currentIndex >= _items.length) {
        if (_repeatMode == PlaylistRepeatMode.all) {
          _currentIndex = 0;
        } else {
          _currentIndex = _items.length - 1;
          notifyListeners();
          return;
        }
      }
    }
    notifyListeners();
  }

  void previous() {
    if (_items.isEmpty) return;
    if (_repeatMode == PlaylistRepeatMode.one) {
      notifyListeners();
      return;
    }
    if (_shuffle) {
      final idx = _shuffleOrder.indexOf(_currentIndex);
      final prevIdx = (idx - 1 + _shuffleOrder.length) % _shuffleOrder.length;
      _currentIndex = _shuffleOrder[prevIdx];
    } else {
      _currentIndex--;
      if (_currentIndex < 0) {
        if (_repeatMode == PlaylistRepeatMode.all) {
          _currentIndex = _items.length - 1;
        } else {
          _currentIndex = 0;
          notifyListeners();
          return;
        }
      }
    }
    notifyListeners();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    if (_shuffle) _generateShuffleOrder();
    notifyListeners();
  }

  void toggleRepeat() {
    const modes = PlaylistRepeatMode.values;
    _repeatMode = modes[(modes.indexOf(_repeatMode) + 1) % modes.length];
    notifyListeners();
  }
}
```

- [ ] **Step 2: Create SleepTimerManager**

Create `android/lib/screens/widgets/sleep_timer_manager.dart`:

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';

class SleepTimerManager extends ChangeNotifier {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _isActive = false;

  bool get isActive => _isActive;
  Duration get remaining => _remaining;

  String get remainingFormatted {
    final m = _remaining.inMinutes;
    final s = _remaining.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void start(Duration duration, VoidCallback onExpired) {
    cancel();
    _remaining = duration;
    _isActive = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _remaining -= const Duration(seconds: 1);
      if (_remaining <= Duration.zero) {
        _isActive = false;
        _timer?.cancel();
        _timer = null;
        _remaining = Duration.zero;
        notifyListeners();
        onExpired();
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _isActive = false;
    _remaining = Duration.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 3: Commit**

```bash
cd /Users/hq/python/code/WiFi-File-Manager
git add android/lib/screens/widgets/playlist_manager.dart android/lib/screens/widgets/sleep_timer_manager.dart
git commit -m "feat: add PlaylistManager and SleepTimerManager"
```

---

### Task 3: MediaInfoPanel & GestureHandler

**Files:**
- Create: `android/lib/screens/widgets/media_info_panel.dart`
- Create: `android/lib/screens/widgets/gesture_handler.dart`

- [ ] **Step 1: Create MediaInfoPanel**

Create `android/lib/screens/widgets/media_info_panel.dart`:

```dart
import 'package:flutter/material.dart';
import '../../utils/format_utils.dart';

class MediaInfoPanel extends StatelessWidget {
  final String fileName;
  final int? fileSize;
  final String? resolution;
  final String? duration;
  final String? format;
  final String? dimensions;
  final String? modifiedDate;

  const MediaInfoPanel({
    super.key,
    required this.fileName,
    this.fileSize,
    this.resolution,
    this.duration,
    this.format,
    this.dimensions,
    this.modifiedDate,
  });

  static void show(BuildContext context, {
    required String fileName,
    int? fileSize,
    String? resolution,
    String? duration,
    String? format,
    String? dimensions,
    String? modifiedDate,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (_) => MediaInfoPanel(
        fileName: fileName,
        fileSize: fileSize,
        resolution: resolution,
        duration: duration,
        format: format,
        dimensions: dimensions,
        modifiedDate: modifiedDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelStyle = TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13);
    final valueStyle = TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('媒体信息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 16),
            _row('文件名', fileName, labelStyle, valueStyle),
            if (fileSize != null) _row('大小', formatSize(fileSize!), labelStyle, valueStyle),
            if (resolution != null) _row('分辨率', resolution!, labelStyle, valueStyle),
            if (dimensions != null) _row('尺寸', dimensions!, labelStyle, valueStyle),
            if (duration != null) _row('时长', duration!, labelStyle, valueStyle),
            if (format != null) _row('格式', format!, labelStyle, valueStyle),
            if (modifiedDate != null) _row('修改日期', modifiedDate!, labelStyle, valueStyle),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, TextStyle labelStyle, TextStyle valueStyle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: labelStyle), Text(value, style: valueStyle)],
      ),
    );
  }
}
```

- [ ] **Step 2: Create GestureHandler**

Create `android/lib/screens/widgets/gesture_handler.dart`:

```dart
import 'package:flutter/material.dart';

enum GestureZone { left, center, right }
enum VerticalZone { leftHalf, rightHalf }

class GestureHandler extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSingleTap;
  final void Function(GestureZone zone)? onDoubleTap;
  final void Function(double delta)? onHorizontalDrag;
  final void Function(VerticalZone zone, double delta)? onVerticalDrag;
  final VoidCallback? onVerticalDragStart;
  final VoidCallback? onVerticalDragEnd;

  const GestureHandler({
    super.key,
    required this.child,
    this.onSingleTap,
    this.onDoubleTap,
    this.onHorizontalDrag,
    this.onVerticalDrag,
    this.onVerticalDragStart,
    this.onVerticalDragEnd,
  });

  @override
  State<GestureHandler> createState() => _GestureHandlerState();
}

class _GestureHandlerState extends State<GestureHandler> {
  bool _isDragging = false;
  double _dragAccumulator = 0.0;

  GestureZone _getHorizontalZone(BuildContext context, Offset localPos) {
    final w = context.size?.width ?? 1;
    if (localPos.dx < w / 3) return GestureZone.left;
    if (localPos.dx > w * 2 / 3) return GestureZone.right;
    return GestureZone.center;
  }

  VerticalZone _getVerticalZone(BuildContext context, Offset localPos) {
    final w = context.size?.width ?? 1;
    return localPos.dx < w / 2 ? VerticalZone.leftHalf : VerticalZone.rightHalf;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onSingleTap,
      onDoubleTapDown: (details) {
        final zone = _getHorizontalZone(context, details.localPosition);
        widget.onDoubleTap?.call(zone);
      },
      onHorizontalDragStart: (_) {
        _isDragging = true;
        _dragAccumulator = 0.0;
      },
      onHorizontalDragUpdate: (details) {
        if (!_isDragging) return;
        _dragAccumulator += details.delta.dx;
        widget.onHorizontalDrag?.call(details.delta.dx);
      },
      onHorizontalDragEnd: (_) {
        _isDragging = false;
        _dragAccumulator = 0.0;
      },
      onVerticalDragStart: (_) {
        _isDragging = true;
        _dragAccumulator = 0.0;
        widget.onVerticalDragStart?.call();
      },
      onVerticalDragUpdate: (details) {
        if (!_isDragging) return;
        final zone = _getVerticalZone(context, details.localPosition);
        widget.onVerticalDrag?.call(zone, details.delta.dy);
      },
      onVerticalDragEnd: (_) {
        _isDragging = false;
        widget.onVerticalDragEnd?.call();
      },
      child: widget.child,
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
cd /Users/hq/python/code/WiFi-File-Manager
git add android/lib/screens/widgets/media_info_panel.dart android/lib/screens/widgets/gesture_handler.dart
git commit -m "feat: add MediaInfoPanel and GestureHandler widgets"
```

---

### Task 4: MediaPlayerScreen Shell

**Files:**
- Create: `android/lib/screens/media_player_screen.dart`

This is the unified shell that wraps all content views. It handles: file type detection, fullscreen, sleep timer, wakelock, and routing to the correct content view.

- [ ] **Step 1: Create MediaPlayerScreen**

Create `android/lib/screens/media_player_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/api_service.dart';
import '../utils/format_utils.dart';
import 'widgets/sleep_timer_manager.dart';
import 'widgets/playlist_manager.dart';

enum MediaType { video, audio, image, text, unsupported }

MediaType detectMediaType(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  if (['mp4', 'avi', 'mkv', 'mov', 'webm'].contains(ext)) return MediaType.video;
  if (['mp3', 'wav', 'flac', 'aac', 'ogg'].contains(ext)) return MediaType.audio;
  if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) return MediaType.image;
  if (['txt', 'json', 'xml', 'html', 'css', 'js', 'ts', 'py', 'md', 'yaml', 'yml',
       'toml', 'csv', 'go', 'rs', 'java', 'c', 'cpp', 'h', 'sh', 'bash', 'sql', 'log'].contains(ext)) {
    return MediaType.text;
  }
  return MediaType.unsupported;
}

class MediaPlayerScreen extends StatefulWidget {
  final ApiService api;
  final String filePath;
  final String fileName;
  final List<Map<String, dynamic>> directoryFiles;

  const MediaPlayerScreen({
    super.key,
    required this.api,
    required this.filePath,
    required this.fileName,
    required this.directoryFiles,
  });

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  late final SleepTimerManager _sleepTimer;
  late final PlaylistManager _playlist;
  late MediaType _mediaType;
  bool _isFullscreen = false;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    _mediaType = detectMediaType(widget.fileName);
    _sleepTimer = SleepTimerManager();
    _playlist = PlaylistManager();

    // Filter files of same type for playlist
    final sameTypeFiles = widget.directoryFiles
        .where((f) => detectMediaType(f['name']) == _mediaType)
        .toList();
    final startIdx = sameTypeFiles.indexWhere((f) => f['name'] == widget.fileName);
    _playlist.setItems(sameTypeFiles, startIndex: startIdx >= 0 ? startIdx : 0);
    _playlist.addListener(_onPlaylistChange);

    if (_mediaType == MediaType.video || _mediaType == MediaType.audio) {
      WakelockPlus.enable();
    }
  }

  @override
  void dispose() {
    _playlist.removeListener(_onPlaylistChange);
    _sleepTimer.dispose();
    _playlist.dispose();
    WakelockPlus.disable();
    if (_isFullscreen) _exitFullscreen();
    super.dispose();
  }

  void _onPlaylistChange() {
    setState(() {});
  }

  void _onSleepTimerExpired() {
    // Subclass/view handles pausing — we just show the snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('定时关闭已触发，播放已暂停')),
    );
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
      if (_isFullscreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        _exitFullscreen();
      }
    });
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  void _showSleepTimerSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('定时关闭', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final m in [15, 30, 45, 60, 90])
                    _timerChip('$m 分钟', Duration(minutes: m)),
                  _timerChip('关闭', Duration.zero, isCancel: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timerChip(String label, Duration duration, {bool isCancel = false}) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        Navigator.pop(context);
        if (isCancel) {
          _sleepTimer.cancel();
        } else {
          _sleepTimer.start(duration, _onSleepTimerExpired);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0f0c29) : const Color(0xFFF5F5FA),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    switch (_mediaType) {
      case MediaType.video:
        return _buildVideoPlaceholder();
      case MediaType.audio:
        return _buildAudioPlaceholder();
      case MediaType.image:
        return _buildImagePlaceholder();
      case MediaType.text:
        return _buildTextPlaceholder();
      case MediaType.unsupported:
        return const Center(child: Text('不支持预览此文件类型'));
    }
  }

  // Placeholders — will be replaced by actual views in subsequent tasks
  Widget _buildVideoPlaceholder() => const Center(child: Text('Video Player — coming in Task 5'));
  Widget _buildAudioPlaceholder() => const Center(child: Text('Audio Player — coming in Task 6'));
  Widget _buildImagePlaceholder() => const Center(child: Text('Image Viewer — coming in Task 7'));
  Widget _buildTextPlaceholder() => const Center(child: Text('Text Viewer — coming in Task 8'));
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/hq/python/code/WiFi-File-Manager
git add android/lib/screens/media_player_screen.dart
git commit -m "feat: add MediaPlayerScreen shell with sleep timer and playlist"
```

---

### Task 5: VideoPlayerView

**Files:**
- Create: `android/lib/screens/widgets/video_player_view.dart`
- Modify: `android/lib/screens/media_player_screen.dart`

- [ ] **Step 1: Create VideoPlayerView**

Create `android/lib/screens/widgets/video_player_view.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import '../../services/api_service.dart';
import '../../utils/format_utils.dart';
import 'gesture_handler.dart';
import 'media_info_panel.dart';
import 'playlist_manager.dart';
import 'sleep_timer_manager.dart';

class VideoPlayerView extends StatefulWidget {
  final ApiService api;
  final String filePath;
  final String fileName;
  final int? fileSize;
  final PlaylistManager playlist;
  final SleepTimerManager sleepTimer;
  final VoidCallback onToggleFullscreen;
  final bool isFullscreen;

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
  });

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _error = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  double _playbackSpeed = 1.0;
  String? _gestureOverlay; // e.g. "-10s", "⏸", "+10s"
  Timer? _overlayTimer;
  double _seekPreview = -1; // normalized 0..1 during horizontal drag
  double _brightnessValue = -1;
  double _volumeValue = -1;

  @override
  void initState() {
    super.initState();
    _initPlayer(widget.filePath);
    widget.playlist.addListener(_onPlaylistChange);
    _resetHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _overlayTimer?.cancel();
    widget.playlist.removeListener(_onPlaylistChange);
    _controller?.dispose();
    super.dispose();
  }

  void _onPlaylistChange() {
    final item = widget.playlist.currentItem;
    if (item['name'] != widget.fileName) {
      _controller?.dispose();
      final newPath = item['path'] ?? widget.filePath.replaceAll(widget.fileName, item['name']);
      _initPlayer(newPath);
    }
  }

  Future<void> _initPlayer(String path) async {
    setState(() { _loading = true; _error = false; });
    try {
      final url = widget.api.getPreviewUrl(path);
      _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await _controller!.initialize();
      _controller!.addListener(_onVideoTick);
      setState(() { _loading = false; });
      _controller!.play();
    } catch (e) {
      setState(() { _loading = false; _error = true; });
    }
  }

  void _onVideoTick() {
    if (mounted && _controller != null) setState(() {});
    // Auto-play next on completion
    if (_controller != null &&
        _controller!.value.position >= _controller!.value.duration &&
        _controller!.value.duration > Duration.zero &&
        !_controller!.value.isPlaying) {
      if (widget.playlist.hasNext) {
        widget.playlist.next();
      }
    }
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller?.value.isPlaying == true) {
        setState(() { _controlsVisible = false; });
      }
    });
  }

  void _toggleControls() {
    setState(() { _controlsVisible = !_controlsVisible; });
    if (_controlsVisible) _resetHideTimer();
  }

  void _showGesture(String text) {
    setState(() { _gestureOverlay = text; });
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() { _gestureOverlay = null; });
    });
  }

  void _seekRelative(int seconds) {
    if (_controller == null) return;
    final pos = _controller!.value.position + Duration(seconds: seconds);
    final clamped = pos < Duration.zero ? Duration.zero : (pos > _controller!.value.duration ? _controller!.value.duration : pos);
    _controller!.seekTo(clamped);
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    setState(() {
      _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
    });
    _resetHideTimer();
  }

  Future<void> _adjustBrightness(double delta) async {
    try {
      final current = await ScreenBrightness().current;
      final next = (current - delta / 300).clamp(0.0, 1.0);
      await ScreenBrightness().setScreenBrightness(next);
      setState(() { _brightnessValue = next; });
    } catch (_) {}
  }

  void _adjustVolume(double delta) {
    VolumeController().getVolume().then((current) {
      final next = (current - delta / 300).clamp(0.0, 1.0);
      VolumeController().setVolume(next);
      setState(() { _volumeValue = next; });
    });
  }

  void _showSpeedSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('播放速度', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((s) {
                  return ChoiceChip(
                    label: Text('${s}x'),
                    selected: _playbackSpeed == s,
                    onSelected: (_) {
                      setState(() { _playbackSpeed = s; });
                      _controller?.setPlaybackSpeed(s);
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error) return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text('加载失败: ${widget.fileName}'),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: () => _initPlayer(widget.filePath), child: const Text('重试')),
        ],
      ),
    );

    return GestureHandler(
      onSingleTap: _toggleControls,
      onDoubleTap: (zone) {
        switch (zone) {
          case GestureZone.left:
            _seekRelative(-10);
            _showGesture('↺ -10s');
          case GestureZone.center:
            _togglePlayPause();
            _showGesture(_controller!.value.isPlaying ? '⏸' : '▶');
          case GestureZone.right:
            _seekRelative(10);
            _showGesture('↻ +10s');
        }
      },
      onHorizontalDrag: (dx) {
        if (_controller == null) return;
        final totalMs = _controller!.value.duration.inMilliseconds;
        if (totalMs <= 0) return;
        final deltaMs = (dx / MediaQuery.of(context).size.width * 2 * 1000).toInt();
        final newPos = _controller!.value.position + Duration(milliseconds: deltaMs);
        final clamped = newPos < Duration.zero ? Duration.zero : (newPos > _controller!.value.duration ? _controller!.value.duration : newPos);
        _controller!.seekTo(clamped);
      },
      onVerticalDrag: (zone, dy) {
        if (zone == VerticalZone.leftHalf) {
          _adjustBrightness(dy);
        } else {
          _adjustVolume(dy);
        }
      },
      onVerticalDragEnd: (_) {
        setState(() { _brightnessValue = -1; _volumeValue = -1; });
      },
      child: Stack(
        children: [
          // Video surface
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
          // Gesture overlay feedback
          if (_gestureOverlay != null)
            Center(
              child: AnimatedOpacity(
                opacity: _gestureOverlay != null ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  alignment: Alignment.center,
                  child: Text(_gestureOverlay!, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          // Brightness overlay
          if (_brightnessValue >= 0)
            _sideIndicator(Icons.brightness_6, '${(_brightnessValue * 100).toInt()}%'),
          // Volume overlay
          if (_volumeValue >= 0)
            _sideIndicator(Icons.volume_up, '${(_volumeValue * 100).toInt()}%', right: true),
          // Controls
          if (_controlsVisible) ...[
            // Top bar
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 4, 8, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent]),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        widget.playlist.currentItem['name'] ?? widget.fileName,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.info_outline, color: Colors.white),
                      onPressed: () => MediaInfoPanel.show(context,
                        fileName: widget.fileName,
                        fileSize: widget.fileSize,
                        resolution: _controller != null
                            ? '${_controller!.value.size.width.toInt()} × ${_controller!.value.size.height.toInt()}'
                            : null,
                        duration: _controller != null ? formatDuration(_controller!.value.duration) : null,
                        format: widget.fileName.split('.').last.toUpperCase(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Bottom control bar
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent]),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Progress bar
                    VideoProgressIndicator(_controller!, allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFF6C63FF),
                        bufferedColor: Colors.white24,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Controls row
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.skip_previous, color: Colors.white, size: 24),
                          onPressed: widget.playlist.hasPrevious ? widget.playlist.previous : null,
                        ),
                        IconButton(
                          icon: Icon(_controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white, size: 32),
                          onPressed: _togglePlayPause,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next, color: Colors.white, size: 24),
                          onPressed: widget.playlist.hasNext ? widget.playlist.next : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${formatDuration(_controller!.value.position)} / ${formatDuration(_controller!.value.duration)}',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        const Spacer(),
                        // Speed
                        GestureDetector(
                          onTap: _showSpeedSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${_playbackSpeed}x', style: const TextStyle(color: Colors.white, fontSize: 11)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Sleep timer
                        GestureDetector(
                          onTap: widget.sleepTimer.isActive ? null : _showSleepTimerSheet,
                          child: widget.sleepTimer.isActive
                              ? Text('⏰ ${widget.sleepTimer.remainingFormatted}',
                                  style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 12))
                              : const Icon(Icons.alarm, color: Colors.white54, size: 20),
                        ),
                        const SizedBox(width: 8),
                        // Fullscreen
                        IconButton(
                          icon: Icon(widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                            color: Colors.white, size: 22),
                          onPressed: widget.onToggleFullscreen,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showSleepTimerSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('定时关闭', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10, runSpacing: 10,
                children: [
                  for (final m in [15, 30, 45, 60, 90])
                    ActionChip(label: Text('$m 分钟'), onPressed: () {
                      Navigator.pop(context);
                      widget.sleepTimer.start(Duration(minutes: m), () {
                        _controller?.pause();
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('定时关闭已触发，播放已暂停')),
                        );
                      });
                    }),
                  ActionChip(label: const Text('关闭'), onPressed: () {
                    Navigator.pop(context);
                    widget.sleepTimer.cancel();
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sideIndicator(IconData icon, String text, {bool right = false}) {
    return Positioned(
      top: MediaQuery.of(context).size.height / 2 - 30,
      left: right ? null : 20,
      right: right ? 20 : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 2: Wire VideoPlayerView into MediaPlayerScreen**

In `media_player_screen.dart`, add import and replace the video placeholder:

Add to imports at top:
```dart
import 'widgets/video_player_view.dart';
```

Replace `_buildVideoPlaceholder`:
```dart
  Widget _buildVideoPlaceholder() {
    final item = _playlist.currentItem;
    return VideoPlayerView(
      api: widget.api,
      filePath: widget.filePath,
      fileName: item['name'] ?? widget.fileName,
      fileSize: item['size'],
      playlist: _playlist,
      sleepTimer: _sleepTimer,
      onToggleFullscreen: _toggleFullscreen,
      isFullscreen: _isFullscreen,
    );
  }
```

- [ ] **Step 3: Commit**

```bash
cd /Users/hq/python/code/WiFi-File-Manager
git add android/lib/screens/widgets/video_player_view.dart android/lib/screens/media_player_screen.dart
git commit -m "feat: add VideoPlayerView with gestures, controls, playlist"
```

---

### Task 6: AudioPlayerView

**Files:**
- Create: `android/lib/screens/widgets/audio_player_view.dart`
- Modify: `android/lib/screens/media_player_screen.dart`

- [ ] **Step 1: Create AudioPlayerView**

Create `android/lib/screens/widgets/audio_player_view.dart`:

```dart
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
  bool _loading = true;
  bool _error = false;
  double _playbackSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _initPlayer(widget.filePath);
    widget.playlist.addListener(_onPlaylistChange);
  }

  @override
  void dispose() {
    widget.playlist.removeListener(_onPlaylistChange);
    _controller?.dispose();
    super.dispose();
  }

  void _onPlaylistChange() {
    final item = widget.playlist.currentItem;
    if (item['name'] != widget.fileName) {
      _controller?.dispose();
      final newPath = item['path'] ?? widget.filePath.replaceAll(widget.fileName, item['name']);
      _initPlayer(newPath);
    }
  }

  Future<void> _initPlayer(String path) async {
    setState(() { _loading = true; _error = false; });
    try {
      final url = widget.api.getPreviewUrl(path);
      _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await _controller!.initialize();
      _controller!.addListener(_onTick);
      setState(() { _loading = false; });
      _controller!.play();
    } catch (e) {
      setState(() { _loading = false; _error = true; });
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
    if (_controller != null &&
        _controller!.value.position >= _controller!.value.duration &&
        _controller!.value.duration > Duration.zero &&
        !_controller!.value.isPlaying) {
      if (widget.playlist.hasNext) widget.playlist.next();
    }
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    setState(() {
      _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentName = widget.playlist.currentItem['name'] ?? widget.fileName;
    final ext = currentName.split('.').last.toLowerCase();
    final formatInfo = '$ext · ${widget.fileSize != null ? formatSize(widget.fileSize!) : ''}';

    if (_loading) return const Center(child: CircularProgressIndicator(color: Colors.white));
    if (_error) return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 12),
        Text('加载失败: $currentName', style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: () => _initPlayer(widget.filePath), child: const Text('重试')),
      ]),
    );

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0xFF1a1040), const Color(0xFF0f0c29)]
              : [const Color(0xFFF0EEFF), const Color(0xFFFFFFFF)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text('正在播放', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.info_outline, color: isDark ? Colors.white : Colors.black87, size: 20),
                    onPressed: () => MediaInfoPanel.show(context,
                      fileName: currentName,
                      fileSize: widget.fileSize,
                      duration: _controller != null ? formatDuration(_controller!.value.duration) : null,
                      format: ext.toUpperCase(),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Album art with glow
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 200, height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      const Color(0xFF6C63FF).withValues(alpha: 0.4),
                      Colors.transparent,
                    ]),
                  ),
                ),
                Container(
                  width: 220, height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFF6C63FF), Color(0xFF48c6ef), Color(0xFFa855f7)],
                    ),
                    boxShadow: [BoxShadow(color: const Color(0xFF6C63FF).withValues(alpha: 0.35), blurRadius: 48, offset: const Offset(0, 16))],
                  ),
                  child: const Icon(Icons.music_note, size: 72, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // File info
            Text(currentName, style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 18, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(formatInfo, style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12)),
            const SizedBox(height: 24),
            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      activeTrackColor: const Color(0xFF6C63FF),
                      inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: _controller!.value.position.inMilliseconds.toDouble().clamp(0, _controller!.value.duration.inMilliseconds.toDouble()),
                      max: _controller!.value.duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                      onChanged: (v) => _controller!.seekTo(Duration(milliseconds: v.toInt())),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(formatDuration(_controller!.value.position),
                          style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12)),
                        Text(formatDuration(_controller!.value.duration),
                          style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Main controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.shuffle, color: widget.playlist.shuffle
                      ? const Color(0xFF6C63FF) : (isDark ? Colors.white38 : Colors.black38), size: 22),
                  onPressed: widget.playlist.toggleShuffle,
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: Icon(Icons.skip_previous, color: isDark ? Colors.white70 : Colors.black54, size: 28),
                  onPressed: widget.playlist.hasPrevious ? widget.playlist.previous : null,
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _togglePlayPause,
                  child: Container(
                    width: 60, height: 60,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF8b5cf6)]),
                      boxShadow: [BoxShadow(color: Color(0x666C63FF), blurRadius: 24, offset: Offset(0, 6))],
                    ),
                    child: Icon(_controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white, size: 30),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.skip_next, color: isDark ? Colors.white70 : Colors.black54, size: 28),
                  onPressed: widget.playlist.hasNext ? widget.playlist.next : null,
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: _repeatIcon(isDark),
                  onPressed: widget.playlist.toggleRepeat,
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Bottom bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _showSpeedSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.black12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${_playbackSpeed}x',
                        style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12)),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _showSleepTimerSheet(isDark),
                    child: widget.sleepTimer.isActive
                        ? Text('⏰ ${widget.sleepTimer.remainingFormatted}',
                            style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 12))
                        : Icon(Icons.alarm, color: isDark ? Colors.white38 : Colors.black38, size: 20),
                  ),
                  const Spacer(),
                  Icon(Icons.volume_up, color: isDark ? Colors.white38 : Colors.black38, size: 18),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 80,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                        activeTrackColor: isDark ? Colors.white54 : Colors.black38,
                        inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
                        thumbColor: isDark ? Colors.white70 : Colors.black54,
                      ),
                      child: Slider(
                        value: 0.7,
                        onChanged: (v) => VolumeController().setVolume(v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _repeatIcon(bool isDark) {
    final color = widget.playlist.repeatMode == PlaylistRepeatMode.off
        ? (isDark ? Colors.white38 : Colors.black38)
        : const Color(0xFF6C63FF);
    if (widget.playlist.repeatMode == PlaylistRepeatMode.one) {
      return Stack(alignment: Alignment.center, children: [
        Icon(Icons.repeat, color: color, size: 22),
        Positioned(right: 0, bottom: 0,
          child: Text('1', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold))),
      ]);
    }
    return Icon(Icons.repeat, color: color, size: 22);
  }

  void _showSpeedSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('播放速度', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8,
                children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((s) {
                  return ChoiceChip(
                    label: Text('${s}x'),
                    selected: _playbackSpeed == s,
                    onSelected: (_) {
                      setState(() { _playbackSpeed = s; });
                      _controller?.setPlaybackSpeed(s);
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSleepTimerSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('定时关闭', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 10,
                children: [
                  for (final m in [15, 30, 45, 60, 90])
                    ActionChip(label: Text('$m 分钟'), onPressed: () {
                      Navigator.pop(context);
                      widget.sleepTimer.start(Duration(minutes: m), () {
                        _controller?.pause();
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('定时关闭已触发，播放已暂停')),
                        );
                      });
                    }),
                  ActionChip(label: const Text('关闭'), onPressed: () {
                    Navigator.pop(context);
                    widget.sleepTimer.cancel();
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Wire AudioPlayerView into MediaPlayerScreen**

In `media_player_screen.dart`, add import and replace placeholder:

```dart
import 'widgets/audio_player_view.dart';
```

Replace `_buildAudioPlaceholder`:
```dart
  Widget _buildAudioPlaceholder() {
    final item = _playlist.currentItem;
    return AudioPlayerView(
      api: widget.api,
      filePath: widget.filePath,
      fileName: item['name'] ?? widget.fileName,
      fileSize: item['size'],
      playlist: _playlist,
      sleepTimer: _sleepTimer,
    );
  }
```

- [ ] **Step 3: Commit**

```bash
cd /Users/hq/python/code/WiFi-File-Manager
git add android/lib/screens/widgets/audio_player_view.dart android/lib/screens/media_player_screen.dart
git commit -m "feat: add AudioPlayerView with album art UI, controls, playlist"
```

---

### Task 7: ImageGalleryView

**Files:**
- Create: `android/lib/screens/widgets/image_gallery_view.dart`
- Modify: `android/lib/screens/media_player_screen.dart`

- [ ] **Step 1: Create ImageGalleryView**

Create `android/lib/screens/widgets/image_gallery_view.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../../services/api_service.dart';
import '../../utils/format_utils.dart';
import 'media_info_panel.dart';
import 'playlist_manager.dart';

class ImageGalleryView extends StatefulWidget {
  final ApiService api;
  final String filePath;
  final String fileName;
  final int? fileSize;
  final PlaylistManager playlist;

  const ImageGalleryView({
    super.key,
    required this.api,
    required this.filePath,
    required this.fileName,
    this.fileSize,
    required this.playlist,
  });

  @override
  State<ImageGalleryView> createState() => _ImageGalleryViewState();
}

class _ImageGalleryViewState extends State<ImageGalleryView> {
  late PageController _pageController;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _slideshowActive = false;
  Timer? _slideshowTimer;
  int _slideshowInterval = 5; // seconds

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.playlist.currentIndex);
    _resetHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _slideshowTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_slideshowActive) setState(() { _controlsVisible = false; });
    });
  }

  void _toggleControls() {
    if (_slideshowActive) {
      _stopSlideshow();
      return;
    }
    setState(() { _controlsVisible = !_controlsVisible; });
    if (_controlsVisible) _resetHideTimer();
  }

  void _startSlideshow() {
    setState(() { _slideshowActive = true; _controlsVisible = false; });
    _slideshowTimer = Timer.periodic(Duration(seconds: _slideshowInterval), (_) {
      if (widget.playlist.hasNext) {
        widget.playlist.next();
        _pageController.animateToPage(
          widget.playlist.currentIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        _stopSlideshow();
      }
    });
  }

  void _stopSlideshow() {
    _slideshowTimer?.cancel();
    setState(() { _slideshowActive = false; _controlsVisible = true; });
    _resetHideTimer();
  }

  void _showSlideshowOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('幻灯片间隔', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10, runSpacing: 10,
                children: [3, 5, 10, 30].map((s) {
                  return ChoiceChip(
                    label: Text('$s 秒'),
                    selected: _slideshowInterval == s,
                    onSelected: (_) {
                      setState(() { _slideshowInterval = s; });
                      Navigator.pop(context);
                      _startSlideshow();
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentName = widget.playlist.currentItem['name'] ?? widget.fileName;
    final total = widget.playlist.items.length;
    final current = widget.playlist.currentIndex + 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Gallery
          PhotoViewGallery.builder(
            pageController: _pageController,
            itemCount: total,
            builder: (ctx, index) {
              final item = widget.playlist.items[index];
              final path = item['path'] ?? widget.filePath.replaceAll(widget.fileName, item['name']);
              final url = widget.api.getPreviewUrl(path);
              return PhotoViewGalleryPageOptions(
                imageProvider: NetworkImage(url),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
                heroAttributes: PhotoViewHeroAttributes(tag: 'image_$index'),
              );
            },
            onPageChanged: (index) {
              widget.playlist.setItems(widget.playlist.items, startIndex: index);
            },
            backgroundDecoration: const BoxDecoration(color: Colors.black),
          ),
          // Page indicator
          if (_controlsVisible || _slideshowActive)
            Positioned(
              bottom: 80, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$current / $total',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ),
            ),
          // Top bar
          if (_controlsVisible)
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 4, 8, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent]),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(currentName,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        overflow: TextOverflow.ellipsis),
                    ),
                    IconButton(
                      icon: const Icon(Icons.slideshow, color: Colors.white, size: 20),
                      onPressed: _showSlideshowOptions,
                    ),
                    IconButton(
                      icon: const Icon(Icons.info_outline, color: Colors.white, size: 20),
                      onPressed: () => MediaInfoPanel.show(context,
                        fileName: currentName,
                        fileSize: widget.fileSize,
                        format: currentName.split('.').last.toUpperCase(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Bottom bar
          if (_controlsVisible)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent]),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _bottomAction(Icons.share, '分享', () {}),
                    const SizedBox(width: 28),
                    _bottomAction(Icons.download, '下载', () {}),
                  ],
                ),
              ),
            ),
          // Slideshow indicator
          if (_slideshowActive)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              right: 16,
              child: GestureDetector(
                onTap: _stopSlideshow,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stop, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('停止幻灯片', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bottomAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Wire ImageGalleryView into MediaPlayerScreen**

In `media_player_screen.dart`, add import and replace placeholder:

```dart
import 'widgets/image_gallery_view.dart';
```

Replace `_buildImagePlaceholder`:
```dart
  Widget _buildImagePlaceholder() {
    final item = _playlist.currentItem;
    return ImageGalleryView(
      api: widget.api,
      filePath: widget.filePath,
      fileName: item['name'] ?? widget.fileName,
      fileSize: item['size'],
      playlist: _playlist,
    );
  }
```

- [ ] **Step 3: Commit**

```bash
cd /Users/hq/python/code/WiFi-File-Manager
git add android/lib/screens/widgets/image_gallery_view.dart android/lib/screens/media_player_screen.dart
git commit -m "feat: add ImageGalleryView with gestures, slideshow, info panel"
```

---

### Task 8: TextCodeView

**Files:**
- Create: `android/lib/screens/widgets/text_code_view.dart`
- Modify: `android/lib/screens/media_player_screen.dart`

- [ ] **Step 1: Create TextCodeView**

Create `android/lib/screens/widgets/text_code_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:dio/dio.dart';
import '../../services/api_service.dart';
import '../../utils/format_utils.dart';
import 'media_info_panel.dart';

class TextCodeView extends StatefulWidget {
  final ApiService api;
  final String filePath;
  final String fileName;
  final int? fileSize;

  const TextCodeView({
    super.key,
    required this.api,
    required this.filePath,
    required this.fileName,
    this.fileSize,
  });

  @override
  State<TextCodeView> createState() => _TextCodeViewState();
}

class _TextCodeViewState extends State<TextCodeView> {
  String? _content;
  bool _loading = true;
  bool _error = false;
  bool _searchVisible = false;
  bool _wordWrap = true;
  String _searchQuery = '';
  List<int> _matchLines = [];
  int _currentMatchIndex = -1;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  int _themeIndex = 0; // 0=auto, 1=mocha, 2=github, 3=monokai

  static const _themes = [
    {'name': '跟随系统', 'dark': atomOneDarkTheme, 'light': githubTheme},
    {'name': 'Catppuccin Mocha', 'dark': atomOneDarkTheme, 'light': atomOneDarkTheme},
    {'name': 'GitHub Light', 'dark': githubTheme, 'light': githubTheme},
    {'name': 'Monokai', 'dark': monokaiSublimeTheme, 'light': monokaiSublimeTheme},
  ];

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _ext => widget.fileName.split('.').last.toLowerCase();

  Map<String, TextStyle> get _currentTheme {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_themeIndex == 0) return isDark ? atomOneDarkTheme : githubTheme;
    final theme = _themes[_themeIndex];
    return isDark ? (theme['dark'] as Map<String, TextStyle>) : (theme['light'] as Map<String, TextStyle>);
  }

  Future<void> _loadContent() async {
    setState(() { _loading = true; _error = false; });
    try {
      final url = widget.api.getPreviewUrl(widget.filePath);
      final resp = await Dio().get(url);
      setState(() { _content = resp.data.toString(); _loading = false; _wordWrap = !isCodeFile(_ext); });
    } catch (e) {
      setState(() { _loading = false; _error = true; });
    }
  }

  void _onSearchChanged(String query) {
    if (_content == null) return;
    _searchQuery = query;
    final lines = _content!.split('\n');
    _matchLines = [];
    for (int i = 0; i < lines.length; i++) {
      if (query.isNotEmpty && lines[i].toLowerCase().contains(query.toLowerCase())) {
        _matchLines.add(i);
      }
    }
    _currentMatchIndex = _matchLines.isNotEmpty ? 0 : -1;
    setState(() {});
    if (_currentMatchIndex >= 0) _scrollToLine(_matchLines[_currentMatchIndex]);
  }

  void _scrollToLine(int line) {
    final target = (line * 20.0).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void _nextMatch() {
    if (_matchLines.isEmpty) return;
    _currentMatchIndex = (_currentMatchIndex + 1) % _matchLines.length;
    setState(() {});
    _scrollToLine(_matchLines[_currentMatchIndex]);
  }

  void _prevMatch() {
    if (_matchLines.isEmpty) return;
    _currentMatchIndex = (_currentMatchIndex - 1 + _matchLines.length) % _matchLines.length;
    setState(() {});
    _scrollToLine(_matchLines[_currentMatchIndex]);
  }

  void _showThemePicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('代码主题', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              for (int i = 0; i < _themes.length; i++)
                ListTile(
                  title: Text(_themes[i]['name'] as String),
                  trailing: _themeIndex == i ? const Icon(Icons.check, color: Color(0xFF6C63FF)) : null,
                  onTap: () { setState(() { _themeIndex = i; }); Navigator.pop(context); },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1e1e2e) : const Color(0xFFFAFAFA);
    final lineNumColor = isDark ? const Color(0xFF585b70) : const Color(0xFF999999);
    final statusBarBg = isDark ? const Color(0xFF181825) : const Color(0xFFF0F0F0);

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error) return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 12),
        Text('加载失败: ${widget.fileName}'),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: _loadContent, child: const Text('重试')),
      ]),
    );

    final lines = _content!.split('\n');
    final langName = getLanguageName(_ext);

    return Column(
      children: [
        // Top bar
        Container(
          color: statusBarBg,
          padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 4, 8, 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(widget.fileName,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                  overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                icon: Icon(_searchVisible ? Icons.close : Icons.search,
                  color: isDark ? Colors.white54 : Colors.black54, size: 20),
                onPressed: () {
                  setState(() { _searchVisible = !_searchVisible; });
                  if (!_searchVisible) { _searchController.clear(); _onSearchChanged(''); }
                },
              ),
              IconButton(
                icon: Icon(Icons.palette, color: isDark ? Colors.white54 : Colors.black54, size: 20),
                onPressed: _showThemePicker,
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: isDark ? Colors.white54 : Colors.black54, size: 20),
                onSelected: (v) {
                  if (v == 'wrap') setState(() { _wordWrap = !_wordWrap; });
                  if (v == 'info') MediaInfoPanel.show(context,
                    fileName: widget.fileName,
                    fileSize: widget.fileSize,
                    format: '$langName · UTF-8',
                  );
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'wrap', child: Text(_wordWrap ? '关闭自动换行' : '开启自动换行')),
                  const PopupMenuItem(value: 'info', child: Text('文件信息')),
                ],
              ),
            ],
          ),
        ),
        // Search bar
        if (_searchVisible)
          Container(
            color: bgColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '搜索...',
                      hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black30),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF313244) : const Color(0xFFEEEEEE),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                if (_matchLines.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text('${_currentMatchIndex + 1}/${_matchLines.length}',
                    style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12)),
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_up, size: 18,
                      color: isDark ? Colors.white54 : Colors.black54),
                    onPressed: _prevMatch, padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  ),
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_down, size: 18,
                      color: isDark ? Colors.white54 : Colors.black54),
                    onPressed: _nextMatch, padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  ),
                ],
              ],
            ),
          ),
        // Code content
        Expanded(
          child: Container(
            color: bgColor,
            child: _wordWrap
                ? _buildWrappedLines(lines, lineNumColor, isDark)
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildWrappedLines(lines, lineNumColor, isDark, wrap: false),
                  ),
          ),
        ),
        // Status bar
        Container(
          color: statusBarBg,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$langName · UTF-8',
                style: TextStyle(color: isDark ? const Color(0xFF585b70) : Colors.black38, fontSize: 11)),
              Text('${lines.length} 行 · ${widget.fileSize != null ? formatSize(widget.fileSize!) : ''}',
                style: TextStyle(color: isDark ? const Color(0xFF585b70) : Colors.black38, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWrappedLines(List<String> lines, Color lineNumColor, bool isDark, {bool wrap = true}) {
    return ListView.builder(
      controller: _scrollController,
      shrinkWrap: !wrap,
      physics: wrap ? null : const NeverScrollableScrollPhysics(),
      itemCount: lines.length,
      itemBuilder: (ctx, i) {
        final isSearchMatch = _matchLines.contains(i);
        final isCurrentMatch = _currentMatchIndex >= 0 && _matchLines[_currentMatchIndex] == i;
        return Container(
          color: isCurrentMatch
              ? (isDark ? const Color(0xFF3d2f00) : const Color(0xFFFFF3CD))
              : isSearchMatch
                  ? (isDark ? const Color(0xFF2a2300) : const Color(0xFFFFF8E1))
                  : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                padding: const EdgeInsets.only(right: 12, top: 2),
                child: Text('${i + 1}',
                  textAlign: TextAlign.right,
                  style: TextStyle(color: lineNumColor, fontSize: 11, height: 1.6)),
              ),
              Expanded(
                child: Text(
                  lines[i],
                  style: TextStyle(
                    color: isDark ? const Color(0xFFcdd6f4) : Colors.black87,
                    fontSize: 13,
                    height: 1.6,
                    fontFamily: 'monospace',
                  ),
                  softWrap: wrap,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 2: Wire TextCodeView into MediaPlayerScreen**

In `media_player_screen.dart`, add import and replace placeholder:

```dart
import 'widgets/text_code_view.dart';
```

Replace `_buildTextPlaceholder`:
```dart
  Widget _buildTextPlaceholder() {
    final item = _playlist.currentItem;
    return TextCodeView(
      api: widget.api,
      filePath: widget.filePath,
      fileName: item['name'] ?? widget.fileName,
      fileSize: item['size'],
    );
  }
```

- [ ] **Step 3: Commit**

```bash
cd /Users/hq/python/code/WiFi-File-Manager
git add android/lib/screens/widgets/text_code_view.dart android/lib/screens/media_player_screen.dart
git commit -m "feat: add TextCodeView with syntax highlight, search, themes"
```

---

### Task 9: Update FileListScreen Navigation

**Files:**
- Modify: `android/lib/screens/file_list_screen.dart`

- [ ] **Step 1: Update FileListScreen to use MediaPlayerScreen**

In `file_list_screen.dart`:

1. Replace the import:
```dart
// Remove: import 'file_preview_screen.dart';
import 'media_player_screen.dart';
```

2. Replace the `_onItemTap` method's else branch (lines 54-62):

```dart
  void _onItemTap(Map<String, dynamic> item) {
    if (item['type'] == 'folder') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FileListScreen(
            api: widget.api,
            path: '$_currentPath/${item['name']}',
            title: item['name'],
          ),
        ),
      );
    } else {
      final filePath = '$_currentPath/${item['name']}';
      final directoryFiles = _items
          .where((f) => f['type'] == 'file')
          .map((f) => {
                'name': f['name'] as String,
                'size': f['size'] as int,
                'path': '$_currentPath/${f['name']}' as String,
              })
          .toList();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MediaPlayerScreen(
            api: widget.api,
            filePath: filePath,
            fileName: item['name'],
            directoryFiles: directoryFiles,
          ),
        ),
      );
    }
  }
```

- [ ] **Step 2: Verify build compiles**

Run: `cd android && flutter analyze`
Expected: No errors (warnings are acceptable).

- [ ] **Step 3: Commit**

```bash
cd /Users/hq/python/code/WiFi-File-Manager
git add android/lib/screens/file_list_screen.dart
git commit -m "feat: route file taps to MediaPlayerScreen with playlist support"
```

---

### Task 10: Screen Lock for Video Player

**Files:**
- Modify: `android/lib/screens/widgets/video_player_view.dart`

- [ ] **Step 1: Add screen lock toggle to VideoPlayerView**

In `video_player_view.dart`, add a `_locked` state variable and lock/unlock UI:

Add state variable:
```dart
bool _locked = false;
```

Add to the top-level `Stack` in `build()`, as a final positioned layer (after the controls):
```dart
          // Lock button (visible when controls visible and not locked)
          if (_controlsVisible && !_locked)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).size.height / 2 - 20,
              child: GestureDetector(
                onTap: () { setState(() { _locked = true; _controlsVisible = false; }); },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.lock_open, color: Colors.white70, size: 20),
                ),
              ),
            ),
          // Unlock button (visible when locked, single tap to unlock)
          if (_locked)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).size.height / 2 - 20,
              child: GestureDetector(
                onTap: () { setState(() { _locked = false; _controlsVisible = true; }); _resetHideTimer(); },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.lock, color: Colors.white70, size: 20),
                ),
              ),
            ),
```

Modify `GestureHandler` to disable gestures when locked:
```dart
      child: GestureHandler(
        onSingleTap: _locked ? null : _toggleControls,
        onDoubleTap: _locked ? null : (zone) { ... },
        onHorizontalDrag: _locked ? null : (dx) { ... },
        onVerticalDrag: _locked ? null : (zone, dy) { ... },
        onVerticalDragEnd: _locked ? null : (_) { ... },
```

- [ ] **Step 2: Commit**

```bash
cd /Users/hq/python/code/WiFi-File-Manager
git add android/lib/screens/widgets/video_player_view.dart
git commit -m "feat: add screen lock toggle to video player"
```

---

### Task 11: Adaptive Theme & Final Integration

**Files:**
- Modify: `android/lib/main.dart`

- [ ] **Step 1: Add dark theme support to main.dart**

Update `android/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ApiService();
    return MaterialApp(
      title: 'WiFi File Manager',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C63FF),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C63FF),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: LoginScreen(api: api),
    );
  }
}
```

- [ ] **Step 2: Full build verification**

Run: `cd android && flutter analyze`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/hq/python/code/WiFi-File-Manager
git add android/lib/main.dart
git commit -m "feat: add adaptive dark/light theme with purple accent"
```
