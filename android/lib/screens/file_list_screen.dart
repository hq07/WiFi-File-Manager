// android/lib/screens/file_list_screen.dart
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../services/layout_prefs.dart';
import '../services/history_service.dart';
import '../services/favorites_service.dart';
import '../utils/format_utils.dart';
import '../utils/snackbar_utils.dart';
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
  late SortField _sortField;
  late bool _sortAscending;

  String _joinPath(String base, String name) {
    if (base.endsWith('/')) return '$base$name';
    return '$base/$name';
  }

  @override
  void initState() {
    super.initState();
    _currentPath = widget.path.replaceAll(RegExp(r'/+'), '/');
    _layoutMode = widget.layoutPrefs.layoutMode;
    _sortField = widget.layoutPrefs.sortField;
    _sortAscending = widget.layoutPrefs.sortAscending;
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() { _loading = true; });
    try {
      final data = await widget.api.listFiles(_currentPath);
      final items = List<dynamic>.from(data['items']);
      _sortItems(items);
      setState(() { _items = items; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; });
      if (mounted) {
        showCopyableSnackBar(context, 'Error: $e', isError: true);
      }
    }
  }

  void _sortItems(List<dynamic> items) {
    items.sort((a, b) {
      final aIsFolder = a['type'] == 'folder';
      final bIsFolder = b['type'] == 'folder';
      if (aIsFolder != bIsFolder) return aIsFolder ? -1 : 1;

      int cmp;
      switch (_sortField) {
        case SortField.size:
          cmp = (a['size'] as int).compareTo(b['size'] as int);
          break;
        case SortField.date:
          cmp = (a['modified'] as String).compareTo(b['modified'] as String);
          break;
        case SortField.name:
          cmp = (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('排序方式', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            for (final field in SortField.values)
              ListTile(
                leading: Icon(
                  field == SortField.name ? Icons.sort_by_alpha
                      : field == SortField.size ? Icons.data_usage
                      : Icons.calendar_today,
                  color: _sortField == field ? Theme.of(context).colorScheme.primary : null,
                ),
                title: Text(
                  field == SortField.name ? '名称'
                      : field == SortField.size ? '大小'
                      : '修改日期',
                  style: TextStyle(
                    fontWeight: _sortField == field ? FontWeight.bold : FontWeight.normal,
                    color: _sortField == field ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
                trailing: _sortField == field
                    ? Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    if (_sortField == field) {
                      _sortAscending = !_sortAscending;
                    } else {
                      _sortField = field;
                      _sortAscending = true;
                    }
                    widget.layoutPrefs.sortField = _sortField;
                    widget.layoutPrefs.sortAscending = _sortAscending;
                    _sortItems(_items);
                  });
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _toggleLayout() {
    setState(() {
      _layoutMode = _layoutMode == LayoutMode.list ? LayoutMode.grid : LayoutMode.list;
      widget.layoutPrefs.layoutMode = _layoutMode;
    });
  }

  void _onItemTap(Map<String, dynamic> item) {
    if (item['type'] == 'folder') {
      final folderPath = item['path'] as String? ?? _joinPath(_currentPath, item['name']);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FileListScreen(
            api: widget.api,
            layoutPrefs: widget.layoutPrefs,
            path: folderPath,
            title: item['name'],
            historyService: widget.historyService,
            favoritesService: widget.favoritesService,
            historyRefresh: widget.historyRefresh,
          ),
        ),
      );
    } else {
      final filePath = '${_joinPath(_currentPath, item['name'])}';
      final directoryFiles = _items
          .where((f) => f['type'] == 'file')
          .map((f) => {
                'name': f['name'] as String,
                'size': f['size'] as int,
                'path': '${_joinPath(_currentPath, f['name'])}',
                if (f.containsKey('display_aspect_ratio'))
                  'display_aspect_ratio': f['display_aspect_ratio'],
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
            initialPositionMs: () {
              final entry = widget.historyService?.getEntry(filePath);
              return (entry != null && !entry.completed) ? entry.lastPositionMs : 0;
            }(),
          ),
        ),
      );
    }
  }

  void _onItemLongPress(Map<String, dynamic> item) {
    final itemPath = '${_joinPath(_currentPath, item['name'])}';
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
    final filePath = '${_joinPath(_currentPath, item['name'])}';
    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/${item['name']}';
    try {
      await widget.api.downloadFile(filePath, savePath, (received, total) {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloaded to $savePath')));
      }
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, 'Download failed: $e', isError: true);
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要将 "${item['name']}" 移入废纸篓吗？'),
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
        await widget.api.trashFile('${_joinPath(_currentPath, item['name'])}');
        _loadFiles();
      } catch (e) {
        if (mounted) {
          showCopyableSnackBar(context, '删除失败: $e', isError: true);
        }
      }
    }
  }

  Future<void> _showFolderInfo(Map<String, dynamic> item) async {
    final folderPath = item['path'] as String? ?? _joinPath(_currentPath, item['name']);
    try {
      final info = await widget.api.getFolderInfo(folderPath);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(item['name']),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoRow(Icons.videocam, '视频', info['video'] ?? 0, Colors.red),
              _infoRow(Icons.image, '图片', info['image'] ?? 0, Colors.blue),
              _infoRow(Icons.audiotrack, '音频', info['audio'] ?? 0, Colors.green),
              _infoRow(Icons.insert_drive_file, '其他', info['other'] ?? 0, Colors.grey),
              const Divider(),
              _infoRow(Icons.folder, '子文件夹', info['folder'] ?? 0, Colors.amber),
              if (info['truncated'] == true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('文件过多，统计可能不完整', style: TextStyle(fontSize: 12, color: Colors.orange)),
                ),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
        ),
      );
    } catch (e) {
      if (mounted) showCopyableSnackBar(context, '获取失败: $e', isError: true);
    }
  }

  Widget _infoRow(IconData icon, String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 15)),
          const Spacer(),
          Text('$count', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
    );
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
        await widget.api.renameFile('${_joinPath(_currentPath, item['name'])}', newName);
        _loadFiles();
      } catch (e) {
        if (mounted) {
          showCopyableSnackBar(context, '重命名失败: $e', isError: true);
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
      final filePath = '${_joinPath(_currentPath, name)}';
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
      return Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(child: Icon(Icons.folder, color: Colors.amber, size: 48)),
          ),
          Positioned(
            right: 2, top: 2,
            child: GestureDetector(
              onTap: () => _showFolderInfo(item),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      );
    }
    final name = item['name'] as String;
    final ext = name.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
    final isVideo = ['mp4', 'avi', 'mkv', 'mov', 'webm'].contains(ext);
    if ((isImage || isVideo) && widget.layoutPrefs.showThumbnails) {
      final filePath = '${_joinPath(_currentPath, name)}';
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
        final isFolder = item['type'] == 'folder';
        return ListTile(
          key: ValueKey(item['path'] ?? item['name']),
          leading: _buildThumbnail(item),
          title: Text(item['name']),
          subtitle: metaLine.isNotEmpty ? Text(metaLine, style: const TextStyle(fontSize: 12)) : null,
          trailing: isFolder ? IconButton(
            icon: Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
            onPressed: () => _showFolderInfo(item),
          ) : null,
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
          key: ValueKey(item['path'] ?? item['name']),
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
            icon: const Icon(Icons.sort),
            onPressed: _showSortSheet,
            tooltip: '排序',
          ),
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
