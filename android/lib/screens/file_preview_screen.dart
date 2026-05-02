// android/lib/screens/file_preview_screen.dart
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';

class FilePreviewScreen extends StatefulWidget {
  final ApiService api;
  final String path;
  final String name;
  const FilePreviewScreen({super.key, required this.api, required this.path, required this.name});

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  VideoPlayerController? _videoCtrl;
  String? _textContent;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  String get _ext => widget.name.split('.').last.toLowerCase();

  bool get _isImage => ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(_ext);
  bool get _isVideo => ['mp4', 'avi', 'mkv', 'mov', 'webm'].contains(_ext);
  bool get _isAudio => ['mp3', 'wav', 'flac', 'aac', 'ogg'].contains(_ext);
  bool get _isText => ['txt', 'json', 'xml', 'html', 'css', 'js', 'py', 'md', 'yaml', 'yml', 'toml', 'csv'].contains(_ext);

  Future<void> _loadPreview() async {
    final url = widget.api.getPreviewUrl(widget.path);
    try {
      if (_isText) {
        final resp = await Dio().get(url);
        setState(() { _textContent = resp.data.toString(); _loading = false; });
      } else if (_isVideo || _isAudio) {
        _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(url));
        await _videoCtrl!.initialize();
        setState(() { _loading = false; });
      } else {
        setState(() { _loading = false; });
      }
    } catch (e) {
      setState(() { _textContent = 'Failed to load: $e'; _loading = false; });
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.api.getPreviewUrl(widget.path);
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _isImage
              ? PhotoView(imageProvider: NetworkImage(url))
              : (_isVideo || _isAudio)
                  ? _buildPlayer()
                  : _isText
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(_textContent ?? ''),
                        )
                      : const Center(child: Text('Preview not available')),
    );
  }

  Widget _buildPlayer() {
    if (_videoCtrl == null || !_videoCtrl!.value.isInitialized) {
      return const Center(child: Text('Failed to load media'));
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: _videoCtrl!.value.aspectRatio,
          child: VideoPlayer(_videoCtrl!),
        ),
        VideoProgressIndicator(_videoCtrl!, allowScrubbing: true),
        IconButton(
          icon: Icon(_videoCtrl!.value.isPlaying ? Icons.pause : Icons.play_arrow),
          iconSize: 48,
          onPressed: () {
            setState(() {
              _videoCtrl!.value.isPlaying ? _videoCtrl!.pause() : _videoCtrl!.play();
            });
          },
        ),
      ],
    );
  }
}
