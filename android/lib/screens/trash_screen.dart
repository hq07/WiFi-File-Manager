import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/format_utils.dart';
import '../utils/snackbar_utils.dart';

class TrashScreen extends StatefulWidget {
  final ApiService api;
  final String subPath;
  final String title;
  const TrashScreen({
    super.key,
    required this.api,
    this.subPath = '',
    this.title = '废纸篓',
  });

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<dynamic> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    setState(() => _loading = true);
    try {
      final items = await widget.api.getTrash(path: widget.subPath);
      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showCopyableSnackBar(context, '加载失败: $e', isError: true);
    }
  }

  void _openFolder(Map<String, dynamic> item) {
    final subPath = widget.subPath.isEmpty
        ? item['name']
        : '${widget.subPath}/${item['name']}';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrashScreen(
          api: widget.api,
          subPath: subPath,
          title: item['name'],
        ),
      ),
    ).then((_) => _loadTrash());
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    try {
      await widget.api.restoreTrash(
        widget.subPath.isEmpty ? item['name'] : '${widget.subPath}/${item['name']}',
      );
      _loadTrash();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已恢复 "${item['name']}"')));
      }
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, '恢复失败: $e', isError: true);
      }
    }
  }

  Future<void> _permanentDelete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('永久删除'),
        content: Text('确定要永久删除 "${item['name']}" 吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('永久删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.deleteFile(item['path']);
      _loadTrash();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已永久删除')));
      }
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, '删除失败: $e', isError: true);
      }
    }
  }

  Future<void> _emptyTrash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空废纸篓'),
        content: Text('确定要永久删除废纸篓中的 ${_items.length} 个项目吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.emptyTrash();
      _loadTrash();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('废纸篓已清空')));
      }
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, '清空失败: $e', isError: true);
      }
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch((timestamp as num).toInt() * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isRoot = widget.subPath.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title}${_items.isNotEmpty ? ' (${_items.length})' : ''}'),
        actions: [
          if (isRoot && _items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空废纸篓',
              onPressed: _emptyTrash,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        isRoot ? '废纸篓是空的' : '文件夹是空的',
                        style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTrash,
                  child: ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final item = _items[i];
                      final isDir = item['is_dir'] == true;
                      return ListTile(
                        leading: Icon(
                          isDir ? Icons.folder : Icons.insert_drive_file,
                          color: isDir ? Colors.amber : Colors.teal,
                        ),
                        title: Text(item['name'], maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          () {
                            final parts = <String>[];
                            if (!isDir) parts.add(formatSize(item['size']));
                            parts.add(_formatDate(item['deleted_at']));
                            final orig = item['original_path'] as String? ?? '';
                            if (orig.isNotEmpty) parts.add(orig);
                            return parts.join(' · ');
                          }(),
                          style: const TextStyle(fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.restore, color: Colors.teal),
                              tooltip: '恢复',
                              onPressed: () => _restore(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_forever, color: Colors.red),
                              tooltip: '永久删除',
                              onPressed: () => _permanentDelete(item),
                            ),
                          ],
                        ),
                        onTap: isDir ? () => _openFolder(item) : null,
                      );
                    },
                  ),
                ),
    );
  }
}
