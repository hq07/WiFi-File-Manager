// android/lib/screens/file_list_screen.dart
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../services/layout_prefs.dart';
import '../services/history_service.dart';
import '../services/favorites_service.dart';
import '../utils/format_utils.dart';
import 'media_player_screen.dart';
import 'widgets/preview_image.dart';

class FileListScreen extends StatefulWidget {
  final ApiService api;
  final LayoutPrefs layoutPrefs;
  final String path;
  final String title;
  final HistoryService? historyService;
  final FavoritesService? favoritesService;
  final ValueNotifier<int>? historyRefresh;
  const FileListScreen({
    super.key,
    required this.api,
    required this.layoutPrefs,
    required this.path,
    required this.title,
    this.historyService,
    this.favoritesService,
    this.historyRefresh,
  });

  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  late String _currentPath;
  late LayoutMode _layoutMode;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.path;
    _layoutMode = widget.layoutPrefs.layoutMode;
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() { _loading = true; });
    try {
      final data = await widget.api.listFiles(_currentPath);
      setState(() { _items = data['items']; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _toggleLayout() {
    setState(() {
      _layoutMode = _layoutMode == LayoutMode.list ? LayoutMode.grid : LayoutMode.list;
      widget.layoutPrefs.layoutMode = _layoutMode;
    });
  }

  void _onItemTap(Map<String, dynamic> item) {
    if (item['type'] == 'folder') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FileListScreen(
            api: widget.api,
            layoutPrefs: widget.layoutPrefs,
            path: '$_currentPath/${item['name']}',
            title: item['name'],
            historyService: widget.historyService,
            favoritesService: widget.favoritesService,
            historyRefresh: widget.historyRefresh,
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
                'path': '$_currentPath/${f['name']}',
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
            historyService: widget.historyService,
            layoutPrefs: widget.layoutPrefs,
            initialPositionMs: widget.historyService?.getEntry(filePath)?.lastPositionMs ?? 0,
          ),
        ),
      );
    }
  }

  void _onItemLongPress(Map<String, dynamic> item) {
    final itemPath = '$_currentPath/${item['name']}';
    final isFav = widget.favoritesService?.isFavorite(itemPath) ?? false;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.favoritesService != null)
              ListTile(
                leading: Icon(isFav ? Icons.star : Icons.star_border, color: isFav ? Colors.amber : null),
                title: Text(isFav ? '取消收藏' : '收藏'),
                onTap: () {
                  Navigator.pop(context);
                  widget.favoritesService!.toggle(FavoriteItem(
                    name: item['name'] as String,
                    path: itemPath,
                    type: item['type'] as String,
                    size: item['size'] as int? ?? 0,
                  ));
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(isFav ? '已取消收藏' : '已收藏'), duration: const Duration(seconds: 1)),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('下载'),
              onTap: () { Navigator.pop(context); _downloadFile(item); },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('重命名'),
              onTap: () { Navigator.pop(context); _renameFile(item); },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(context); _confirmDelete(item); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadFile(Map<String, dynamic> item) async {
    final filePath = '$_currentPath/${item['name']}';
    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/${item['name']}';
    try {
      await widget.api.downloadFile(filePath, savePath, (received, total) {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloaded to $savePath')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${item['name']}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await widget.api.deleteFile('$_currentPath/${item['name']}');
        _loadFiles();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
        }
      }
    }
  }

  Future<void> _renameFile(Map<String, dynamic> item) async {
    final controller = TextEditingController(text: item['name']);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != item['name']) {
      try {
        await widget.api.renameFile('$_currentPath/${item['name']}', newName);
        _loadFiles();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重命名失败: $e')));
        }
      }
    }
  }

  IconData _getIcon(String type, String name) {
    if (type == 'folder') return Icons.folder;
    final ext = name.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) return Icons.image;
    if (['mp4', 'avi', 'mkv', 'mov', 'webm'].contains(ext)) return Icons.video_file;
    if (['mp3', 'wav', 'flac', 'aac', 'ogg'].contains(ext)) return Icons.audio_file;
    if (['txt', 'json', 'xml', 'html', 'css', 'js', 'py', 'md'].contains(ext)) return Icons.description;
    return Icons.insert_drive_file;
  }

  Widget _buildThumbnail(Map<String, dynamic> item) {
    if (item['type'] == 'folder') {
      return const Icon(Icons.folder, color: Colors.amber, size: 40);
    }
    final name = item['name'] as String;
    final ext = name.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
    final isVideo = ['mp4', 'avi', 'mkv', 'mov', 'webm'].contains(ext);
    if ((isImage || isVideo) && widget.layoutPrefs.showThumbnails) {
      final filePath = '$_currentPath/$name';
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 48, height: 48,
          child: PreviewImage(
            url: widget.api.getPreviewUrl(filePath, thumbnail: isVideo),
            headers: widget.api.previewHeaders,
            fit: BoxFit.cover,
            fallback: Icon(_getIcon(item['type'], name), size: 40),
          ),
        ),
      );
    }
    return Icon(_getIcon(item['type'], name), size: 40);
  }

  Widget _buildGridThumbnail(Map<String, dynamic> item) {
    if (item['type'] == 'folder') {
      return Container(
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: Icon(Icons.folder, color: Colors.amber, size: 48)),
      );
    }
    final name = item['name'] as String;
    final ext = name.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
    final isVideo = ['mp4', 'avi', 'mkv', 'mov', 'webm'].contains(ext);
    if ((isImage || isVideo) && widget.layoutPrefs.showThumbnails) {
      final filePath = '$_currentPath/$name';
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: PreviewImage(
          url: widget.api.getPreviewUrl(filePath, thumbnail: isVideo),
          headers: widget.api.previewHeaders,
          fit: BoxFit.cover,
          fallback: Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Center(child: Icon(_getIcon(item['type'], name), size: 40)),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(child: Icon(_getIcon(item['type'], name), size: 40)),
    );
  }

  String _buildMetaLine(Map<String, dynamic> item) {
    if (item['type'] == 'folder') return '';
    final prefs = widget.layoutPrefs;
    final parts = <String>[];
    if (prefs.showSize) parts.add(formatSize(item['size']));
    if (prefs.showDuration && item['duration'] != null) {
      final dur = (item['duration'] as num).toDouble();
      final min = dur ~/ 60;
      final sec = (dur % 60).toInt();
      parts.add('${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}');
    }
    if (prefs.showResolution && item['resolution'] != null) {
      parts.add(item['resolution']);
    }
    if (prefs.showExtension) {
      final ext = (item['name'] as String).split('.').last.toLowerCase();
      parts.add(ext.toUpperCase());
    }
    if (prefs.showDate && item['modified'] != null) {
      final date = DateTime.tryParse(item['modified']);
      if (date != null) {
        parts.add('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}');
      }
    }
    return parts.join(' · ');
  }

  Widget _buildListView() {
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final item = _items[i];
        final metaLine = _buildMetaLine(item);
        return ListTile(
          leading: _buildThumbnail(item),
          title: Text(item['name']),
          subtitle: metaLine.isNotEmpty ? Text(metaLine, style: const TextStyle(fontSize: 12)) : null,
          onTap: () => _onItemTap(item),
          onLongPress: () => _onItemLongPress(item),
        );
      },
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.layoutPrefs.gridColumns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final item = _items[i];
        final metaLine = _buildMetaLine(item);
        return GestureDetector(
          onTap: () => _onItemTap(item),
          onLongPress: () => _onItemLongPress(item),
          child: Column(
            children: [
              Expanded(child: _buildGridThumbnail(item)),
              const SizedBox(height: 4),
              Text(
                item['name'],
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              if (metaLine.isNotEmpty)
                Text(
                  metaLine,
                  style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(_layoutMode == LayoutMode.list ? Icons.grid_view : Icons.view_list),
            onPressed: _toggleLayout,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadFiles,
              child: _items.isEmpty
                  ? const Center(child: Text('Empty directory'))
                  : _layoutMode == LayoutMode.list
                      ? _buildListView()
                      : _buildGridView(),
            ),
    );
  }

}
