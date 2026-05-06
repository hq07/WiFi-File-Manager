import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/layout_prefs.dart';
import '../services/history_service.dart';
import '../services/favorites_service.dart';
import '../utils/format_utils.dart';
import 'file_list_screen.dart';
import 'media_player_screen.dart';
import 'widgets/preview_image.dart';

class SearchScreen extends StatefulWidget {
  final ApiService api;
  final LayoutPrefs layoutPrefs;
  final HistoryService historyService;
  final FavoritesService favoritesService;
  final ValueNotifier<int> historyRefresh;

  const SearchScreen({
    super.key,
    required this.api,
    required this.layoutPrefs,
    required this.historyService,
    required this.favoritesService,
    required this.historyRefresh,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _searched = false;
  String _query = '';

  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
  static const _videoExts = {'mp4', 'avi', 'mkv', 'mov', 'webm'};
  static const _audioExts = {'mp3', 'wav', 'flac', 'aac', 'ogg'};

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() { _results = []; _searched = false; _query = ''; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value.trim()));
  }

  Future<void> _search(String query) async {
    setState(() { _loading = true; _query = query; });
    try {
      final data = await widget.api.searchFiles(query);
      final items = (data['items'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (mounted) setState(() { _results = items; _loading = false; _searched = true; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _searched = true; });
    }
  }

  bool _isMedia(String name) {
    final ext = name.split('.').last.toLowerCase();
    return _imageExts.contains(ext) || _videoExts.contains(ext) || _audioExts.contains(ext);
  }

  IconData _fileIcon(String name, String type) {
    if (type == 'folder') return Icons.folder;
    final ext = name.split('.').last.toLowerCase();
    if (_videoExts.contains(ext)) return Icons.video_file;
    if (_audioExts.contains(ext)) return Icons.audio_file;
    if (_imageExts.contains(ext)) return Icons.image;
    return Icons.insert_drive_file;
  }

  Color _fileColor(String name, String type) {
    if (type == 'folder') return Colors.amber;
    final ext = name.split('.').last.toLowerCase();
    if (_videoExts.contains(ext)) return Colors.blue;
    if (_audioExts.contains(ext)) return Colors.purple;
    if (_imageExts.contains(ext)) return Colors.green;
    return Colors.grey;
  }

  void _openItem(Map<String, dynamic> item) {
    final type = item['type'] as String;
    final path = item['path'] as String;
    final name = item['name'] as String;

    if (type == 'folder') {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => FileListScreen(
          api: widget.api,
          layoutPrefs: widget.layoutPrefs,
          historyService: widget.historyService,
          favoritesService: widget.favoritesService,
          path: path,
          title: name,
          historyRefresh: widget.historyRefresh,
        ),
      ));
    } else if (_isMedia(name)) {
      // Collect all media results as directoryFiles for playlist support
      final mediaItems = _results.where((r) =>
        r['type'] == 'file' && _isMedia(r['name'] as String)
      ).toList();
      final directoryFiles = mediaItems.map((r) => {
        'name': r['name'],
        'size': r['size'],
        'path': r['path'],
      }).toList();
      // Find initial position from history
      final historyItem = widget.historyService.getEntry(path);
      final initialPos = (historyItem != null && !historyItem.completed)
          ? historyItem.lastPositionMs : 0;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => MediaPlayerScreen(
          api: widget.api,
          historyService: widget.historyService,
          layoutPrefs: widget.layoutPrefs,
          filePath: path,
          fileName: name,
          directoryFiles: directoryFiles,
          initialPositionMs: initialPos,
        ),
      )).then((_) => widget.historyRefresh.value++);
    } else {
      // Non-media file: jump to parent directory
      final parent = item['parent'] as String;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => FileListScreen(
          api: widget.api,
          layoutPrefs: widget.layoutPrefs,
          historyService: widget.historyService,
          favoritesService: widget.favoritesService,
          path: parent,
          title: parent.split('/').last,
          historyRefresh: widget.historyRefresh,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索文件和文件夹...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.grey),
          ),
          onChanged: _onChanged,
          onSubmitted: (v) { if (v.trim().isNotEmpty) _search(v.trim()); },
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                setState(() { _results = []; _searched = false; _query = ''; });
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_searched) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('输入关键词搜索', style: TextStyle(fontSize: 15, color: Colors.grey.shade400)),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('没有找到「$_query」', style: TextStyle(fontSize: 15, color: Colors.grey.shade400)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final item = _results[i];
        final name = item['name'] as String;
        final type = item['type'] as String;
        final path = item['path'] as String;
        final parent = item['parent'] as String;
        final size = item['size'] as int;
        final ext = name.split('.').last.toLowerCase();
        final isVideo = _videoExts.contains(ext);

        return ListTile(
          leading: _isMedia(name) && type == 'file'
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 48, height: 48,
                    child: PreviewImage(
                      url: widget.api.getPreviewUrl(path, thumbnail: isVideo),
                      headers: widget.api.previewHeaders,
                      fit: BoxFit.cover,
                      fallback: Icon(_fileIcon(name, type), color: _fileColor(name, type), size: 32),
                    ),
                  ),
                )
              : Icon(_fileIcon(name, type), color: _fileColor(name, type), size: 32),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onLongPress: () {
                  Clipboard.setData(ClipboardData(text: path));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('路径已复制'), duration: Duration(seconds: 1)),
                  );
                },
                child: Text(
                  parent,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
              if (type == 'file')
                Text(formatSize(size), style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ],
          ),
          onTap: () => _openItem(item),
        );
      },
    );
  }
}
