// android/lib/screens/file_list_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import 'file_preview_screen.dart';

class FileListScreen extends StatefulWidget {
  final ApiService api;
  final String path;
  final String title;
  const FileListScreen({super.key, required this.api, required this.path, required this.title});

  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  late String _currentPath;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.path;
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
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FilePreviewScreen(api: widget.api, path: filePath, name: item['name']),
        ),
      );
    }
  }

  void _onItemLongPress(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Download'),
              onTap: () { Navigator.pop(context); _downloadFile(item); },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload here'),
              onTap: () { Navigator.pop(context); _uploadHere(); },
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

  Future<void> _uploadHere() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload: use home screen')));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadFiles,
              child: _items.isEmpty
                  ? const Center(child: Text('Empty directory'))
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        return ListTile(
                          leading: Icon(_getIcon(item['type'], item['name'])),
                          title: Text(item['name']),
                          subtitle: item['type'] == 'file'
                              ? Text(_formatSize(item['size']))
                              : null,
                          onTap: () => _onItemTap(item),
                          onLongPress: () => _onItemLongPress(item),
                        );
                      },
                    ),
            ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
