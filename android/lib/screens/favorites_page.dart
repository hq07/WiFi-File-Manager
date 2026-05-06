import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/layout_prefs.dart';
import '../services/history_service.dart';
import '../services/favorites_service.dart';
import '../utils/format_utils.dart';
import 'file_list_screen.dart';
import 'media_player_screen.dart';
import 'widgets/preview_image.dart';

class FavoritesPage extends StatefulWidget {
  final ApiService api;
  final LayoutPrefs layoutPrefs;
  final HistoryService historyService;
  final FavoritesService favoritesService;
  final ValueNotifier<int>? historyRefresh;
  const FavoritesPage({super.key, required this.api, required this.layoutPrefs, required this.historyService, required this.favoritesService, this.historyRefresh});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
  static const _videoExts = {'mp4', 'avi', 'mkv', 'mov', 'webm'};
  static const _audioExts = {'mp3', 'wav', 'flac', 'aac', 'ogg'};

  late List<FavoriteItem> _favorites;
  Map<String, HistoryItem> _historyMap = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    widget.historyRefresh?.addListener(_onRefresh);
  }

  @override
  void dispose() {
    widget.historyRefresh?.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    if (mounted) setState(() => _loadData());
  }

  void _loadData() {
    _favorites = widget.favoritesService.getFavorites();
    _historyMap = {for (final h in widget.historyService.getHistory()) h.path: h};
  }

  Future<void> _refresh() async {
    setState(() => _loadData());
  }

  bool _isMedia(String name) {
    final ext = name.split('.').last.toLowerCase();
    return _videoExts.contains(ext) || _audioExts.contains(ext);
  }

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (_videoExts.contains(ext)) return Icons.video_file;
    if (_audioExts.contains(ext)) return Icons.audio_file;
    if (_imageExts.contains(ext)) return Icons.image;
    return Icons.insert_drive_file;
  }

  bool _hasPreview(String name) {
    final ext = name.split('.').last.toLowerCase();
    return _imageExts.contains(ext) || _videoExts.contains(ext);
  }

  Widget _buildLeading(FavoriteItem item) {
    final isFolder = item.type == 'folder';
    if (isFolder) {
      return const SizedBox(width: 56, height: 56, child: Icon(Icons.folder, color: Colors.amber, size: 32));
    }
    final ext = item.name.split('.').last.toLowerCase();
    final isVideo = _videoExts.contains(ext);
    final fallback = SizedBox(
      width: 56, height: 56,
      child: Icon(_fileIcon(item.name), size: 32, color: Colors.teal),
    );
    if (_hasPreview(item.name)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 56, height: 56,
          child: PreviewImage(
            key: ValueKey(item.path),
            url: widget.api.getPreviewUrl(item.path, thumbnail: isVideo),
            headers: widget.api.previewHeaders,
            fit: BoxFit.cover,
            fallback: fallback,
          ),
        ),
      );
    }
    return fallback;
  }

  Widget? _buildProgress(FavoriteItem item) {
    if (!_isMedia(item.name)) return null;
    final history = _historyMap[item.path];
    if (history == null) return null;
    final progress = history.progress;
    if (progress <= 0 && !history.completed) return null;
    final percent = history.completed ? 100 : (progress * 100).round();
    final color = history.completed ? Colors.green : Colors.teal;
    final label = history.completed ? '已看完' : '已看 $percent%';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: history.completed ? 1.0 : progress,
                minHeight: 4,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _openItem(FavoriteItem item) {
    if (item.type == 'folder') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FileListScreen(
            api: widget.api,
            layoutPrefs: widget.layoutPrefs,
            historyService: widget.historyService,
            favoritesService: widget.favoritesService,
            path: item.path,
            title: item.name,
            historyRefresh: widget.historyRefresh,
          ),
        ),
      );
    } else {
      final history = _historyMap[item.path];
      final initialPos = (history != null && !history.completed) ? history.lastPositionMs : 0;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MediaPlayerScreen(
            api: widget.api,
            historyService: widget.historyService,
            layoutPrefs: widget.layoutPrefs,
            filePath: item.path,
            fileName: item.name,
            directoryFiles: [{'name': item.name, 'size': item.size, 'path': item.path}],
            initialPositionMs: initialPos,
          ),
        ),
      ).then((_) {
        setState(() => _loadData());
        widget.historyRefresh?.value++;
      });
    }
  }

  void _removeFavorite(FavoriteItem item) {
    widget.favoritesService.removeByPath(item.path);
    setState(() => _loadData());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已取消收藏「${item.name}」'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_border, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('还没有收藏的文件', style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('在文件列表中长按可添加收藏', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 80),
        itemCount: _favorites.length,
        itemBuilder: (_, i) {
          final item = _favorites[i];
          final isFolder = item.type == 'folder';
          final progressWidget = _buildProgress(item);
          return Dismissible(
            key: ValueKey(item.path),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: Colors.red,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              return await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('取消收藏'),
                  content: Text('确定要取消收藏「${item.name}」吗？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
                  ],
                ),
              );
            },
            onDismissed: (_) => _removeFavorite(item),
            child: ListTile(
              leading: _buildLeading(item),
              title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isFolder ? item.path : '${formatSize(item.size)} · ${item.path}',
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (progressWidget != null) progressWidget,
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _removeFavorite(item),
              ),
              onTap: () => _openItem(item),
            ),
          );
        },
      ),
    );
  }
}
