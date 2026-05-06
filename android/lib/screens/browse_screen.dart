// android/lib/screens/browse_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/snackbar_utils.dart';

class BrowseScreen extends StatefulWidget {
  final ApiService api;
  const BrowseScreen({super.key, required this.api});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  List<dynamic> _commonPaths = [];
  List<String> _dirs = [];
  String? _currentPath;
  bool _loading = true;
  bool _showingCommonPaths = true;
  final _manualPathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCommonPaths();
  }

  @override
  void dispose() {
    _manualPathController.dispose();
    super.dispose();
  }

  Future<void> _loadCommonPaths() async {
    setState(() => _loading = true);
    try {
      final paths = await widget.api.getCommonPaths();
      setState(() {
        _commonPaths = paths;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        showCopyableSnackBar(context, '加载失败: $e', isError: true);
      }
    }
  }

  Future<void> _browseTo(String path) async {
    setState(() {
      _loading = true;
      _showingCommonPaths = false;
    });
    try {
      final data = await widget.api.browsePath(path);
      setState(() {
        _currentPath = data['path'];
        _dirs = List<String>.from(data['dirs']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        showCopyableSnackBar(context, '无法访问: $e', isError: true);
      }
    }
  }

  Future<void> _shareCurrentPath() async {
    if (_currentPath == null) return;
    try {
      await widget.api.addShare(_currentPath!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加: $_currentPath')),
        );
        Navigator.pop(context, _currentPath);
      }
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, '添加失败: $e', isError: true);
      }
    }
  }

  void _goBack() {
    if (_currentPath == null) return;
    final parent = _currentPath!.substring(0, _currentPath!.lastIndexOf('/'));
    if (parent.isEmpty) {
      _browseTo('/');
    } else {
      _browseTo(parent);
    }
  }

  void _showManualInputDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动输入路径'),
        content: TextField(
          controller: _manualPathController,
          decoration: const InputDecoration(
            hintText: '/path/to/folder',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final path = _manualPathController.text.trim();
              if (path.isNotEmpty) _browseTo(path);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showingCommonPaths ? '选择文件夹' : (_currentPath ?? '')),
        leading: _showingCommonPaths
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() => _showingCommonPaths = true);
                },
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            onPressed: _showManualInputDialog,
            tooltip: '手动输入路径',
          ),
        ],
      ),
      bottomNavigationBar: _currentPath != null && !_showingCommonPaths
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: _shareCurrentPath,
                icon: const Icon(Icons.check),
                label: Text('选择此文件夹: $_currentPath'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _showingCommonPaths
              ? ListView.builder(
                  itemCount: _commonPaths.length,
                  itemBuilder: (context, index) {
                    final p = _commonPaths[index];
                    return ListTile(
                      leading: const Icon(Icons.folder_special, color: Colors.blue),
                      title: Text(p['name']),
                      subtitle: Text(p['path']),
                      onTap: () => _browseTo(p['path']),
                    );
                  },
                )
              : Column(
                  children: [
                    if (_currentPath != '/' && _currentPath != null)
                      ListTile(
                        leading: const Icon(Icons.arrow_upward),
                        title: const Text('上一级'),
                        onTap: _goBack,
                      ),
                    Expanded(
                      child: _dirs.isEmpty
                          ? const Center(child: Text('此目录下没有子文件夹'))
                          : ListView.builder(
                              itemCount: _dirs.length,
                              itemBuilder: (context, index) {
                                final dir = _dirs[index];
                                final fullPath = '$_currentPath/$dir'
                                    .replaceAll('//', '/');
                                return ListTile(
                                  leading: const Icon(Icons.folder, color: Colors.amber),
                                  title: Text(dir),
                                  onTap: () => _browseTo(fullPath),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
