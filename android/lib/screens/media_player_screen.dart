import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/api_service.dart';
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

  Widget _buildVideoPlaceholder() => const Center(child: Text('Video Player — coming in Task 5'));
  Widget _buildAudioPlaceholder() => const Center(child: Text('Audio Player — coming in Task 6'));
  Widget _buildImagePlaceholder() => const Center(child: Text('Image Viewer — coming in Task 7'));
  Widget _buildTextPlaceholder() => const Center(child: Text('Text Viewer — coming in Task 8'));
}
