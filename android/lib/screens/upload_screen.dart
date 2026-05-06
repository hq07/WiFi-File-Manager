// android/lib/screens/upload_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class _UploadItem {
  final String localPath;
  final String relativePath;
  _UploadItem({required this.localPath, required this.relativePath});
}

class UploadScreen extends StatefulWidget {
  final ApiService api;
  const UploadScreen({super.key, required this.api});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  List<dynamic> _shares = [];
  String? _selectedSharePath;
  List<String> _subdirs = [];
  String? _selectedSubdir;
  List<_UploadItem> _files = [];
  bool _isFolderUpload = false;
  double _fileProgress = 0;
  int _completedCount = 0;
  int _skipCount = 0;
  bool _uploading = false;
  bool _cancelled = false;
  String? _currentFileName;
  String? _result;

  @override
  void initState() {
    super.initState();
    _loadShares();
  }

  Future<void> _loadShares() async {
    final shares = await widget.api.getShares();
    setState(() => _shares = shares);
  }

  Future<void> _loadSubdirs(String sharePath) async {
    try {
      final data = await widget.api.browsePath(sharePath);
      final dirs = (data['dirs'] as List?)?.cast<String>() ?? [];
      setState(() {
        _subdirs = dirs;
        _selectedSubdir = null;
      });
    } catch (_) {
      setState(() {
        _subdirs = [];
        _selectedSubdir = null;
      });
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _files = result.files
            .where((f) => f.path != null)
            .map((f) => _UploadItem(localPath: f.path!, relativePath: f.name))
            .toList();
        _isFolderUpload = false;
        _result = null;
      });
    }
  }

  Future<void> _pickFolder() async {
    final dirPath = await FilePicker.getDirectoryPath();
    if (dirPath == null) return;
    final dir = Directory(dirPath);
    final folderName = dirPath.split('/').last;
    final items = <_UploadItem>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final relative = entity.path.substring(dirPath.length + 1);
        items.add(_UploadItem(
          localPath: entity.path,
          relativePath: '$folderName/$relative',
        ));
      }
    }
    if (items.isEmpty) {
      setState(() => _result = '文件夹为空');
      return;
    }
    setState(() {
      _files = items;
      _isFolderUpload = true;
      _result = null;
    });
  }

  Future<void> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || _selectedSharePath == null) return;
    try {
      final parentPath = _selectedSubdir != null
          ? '$_selectedSharePath/$_selectedSubdir'
          : _selectedSharePath!;
      await widget.api.createSubdir(parentPath, name);
      await _loadSubdirs(_selectedSharePath!);
      setState(() => _selectedSubdir = _subdirs.contains(name) ? name : null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已创建文件夹: $name')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
      }
    }
  }

  Future<void> _upload() async {
    if (_files.isEmpty || _selectedSharePath == null) return;
    setState(() {
      _uploading = true;
      _cancelled = false;
      _fileProgress = 0;
      _completedCount = 0;
      _skipCount = 0;
      _result = null;
    });

    final total = _files.length;
    for (int i = 0; i < total; i++) {
      if (_cancelled) break;
      final file = _files[i];
      String relativePath = file.relativePath;
      if (_selectedSubdir != null && _selectedSubdir!.isNotEmpty) {
        relativePath = '$_selectedSubdir/$relativePath';
      }
      setState(() {
        _currentFileName = file.relativePath;
        _fileProgress = 0;
      });
      try {
        await widget.api.uploadFile(
          _selectedSharePath!,
          file.localPath,
          relativePath,
          (sent, total) {
            if (total > 0) setState(() => _fileProgress = sent / total);
          },
        );
        _completedCount++;
      } catch (e) {
        if (e.toString().contains('409')) {
          _skipCount++;
        } else {
          setState(() => _result = '上传失败: ${file.relativePath}\n$e');
          break;
        }
      }
      setState(() {});
    }

    if (!_cancelled) {
      final skipped = _skipCount > 0 ? '，跳过 $_skipCount 个已存在文件' : '';
      setState(() => _result = '上传完成: $_completedCount/$total$skipped');
    }
    setState(() {
      _uploading = false;
      _currentFileName = null;
    });
  }

  void _cancelUpload() {
    setState(() {
      _cancelled = true;
      _result = '已取消（已上传 $_completedCount 个）';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('上传文件')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 文件选择按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploading ? null : _pickFiles,
                    icon: const Icon(Icons.file_upload),
                    label: const Text('选择文件'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _uploading ? null : _pickFolder,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择文件夹'),
                  ),
                ),
              ],
            ),
            if (_files.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '已选 ${_files.length} 个文件${_isFolderUpload ? "（文件夹上传）" : ""}',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
            const SizedBox(height: 16),
            // 目标目录选择
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: '目标目录',
                border: OutlineInputBorder(),
              ),
              value: _selectedSharePath,
              items: _shares.map<DropdownMenuItem<String>>((s) {
                return DropdownMenuItem(
                  value: s['path'] as String,
                  child: Text(s['name'] ?? s['path']),
                );
              }).toList(),
              onChanged: _uploading
                  ? null
                  : (v) {
                      setState(() => _selectedSharePath = v);
                      if (v != null) _loadSubdirs(v);
                    },
            ),
            // 子目录选择
            if (_subdirs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: '子目录（可选）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      value: _selectedSubdir,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('根目录'),
                        ),
                        ..._subdirs.map((d) => DropdownMenuItem(
                              value: d,
                              child: Text(d),
                            )),
                      ],
                      onChanged: _uploading
                          ? null
                          : (v) => setState(() => _selectedSubdir = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.create_new_folder),
                    tooltip: '新建文件夹',
                    onPressed: _uploading ? null : _showCreateFolderDialog,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            // 上传进度
            if (_uploading) ...[
              LinearProgressIndicator(value: _fileProgress > 0 ? _fileProgress : null),
              const SizedBox(height: 8),
              Text(
                '上传中 $_completedCount/${_files.length}  ${(_fileProgress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 13),
              ),
              if (_currentFileName != null)
                Text(
                  _currentFileName!,
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black45),
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _cancelUpload,
                  child: const Text('取消上传'),
                ),
              ),
            ],
            // 结果
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text(
                _result!,
                style: TextStyle(
                  color: _result!.contains('完成') ? Colors.green : Colors.red,
                  fontSize: 14,
                ),
              ),
            ],
            const Spacer(),
            // 上传按钮
            ElevatedButton.icon(
              onPressed: (_files.isNotEmpty &&
                      _selectedSharePath != null &&
                      !_uploading)
                  ? _upload
                  : null,
              icon: const Icon(Icons.cloud_upload),
              label: Text('上传 ${_files.length} 个文件'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
