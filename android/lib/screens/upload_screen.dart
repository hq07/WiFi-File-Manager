// android/lib/screens/upload_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../utils/snackbar_utils.dart';

class _UploadItem {
  final String localPath;
  final String relativePath;
  final String? safUri;
  _UploadItem({required this.localPath, required this.relativePath, this.safUri});
}

class UploadScreen extends StatefulWidget {
  final ApiService api;
  const UploadScreen({super.key, required this.api});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  static const _safChannel = MethodChannel('com.wififilemanager/saf');
  static const _progressChannel = MethodChannel('com.wififilemanager/media');

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
  final ValueNotifier<String> _copyProgress = ValueNotifier('');
  bool _copyCancelled = false;

  @override
  void initState() {
    super.initState();
    _loadShares().then((_) => _autoSelectUploadsDir());
  }

  @override
  void dispose() {
    _copyProgress.dispose();
    _clearUploadCache();
    super.dispose();
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

  String? _cacheDirPath;

  Future<void> _autoSelectUploadsDir() async {
    try {
      final info = await widget.api.getUploadsDir();
      final uploadsPath = info['path'] as String;
      if (_shares.isEmpty) await _loadShares();
      final match = _shares.where((s) => s['path'] == uploadsPath).toList();
      if (match.isNotEmpty && mounted) {
        setState(() => _selectedSharePath = uploadsPath);
        await _loadSubdirs(uploadsPath);
      }
    } catch (_) {}
  }

  Future<void> _pickFolder() async {
    if (Platform.isAndroid) {
      await _pickFolderAndroid();
    } else {
      await _pickFolderFallback();
    }
  }

  Future<void> _pickFolderAndroid() async {
    try {
      final pickResult = await _safChannel.invokeMethod('pickFolderSaf');
      if (pickResult == null) return;

      final folderName = pickResult['folderName'] as String;

      // 后台枚举文件（只列出 URI，不复制）
      final scanResult = await _showCopyProgressDialog(folderName);
      if (scanResult == null || scanResult['cancelled'] == true) return;

      final uris = (scanResult['uris'] as List?)?.cast<String>() ?? [];
      final relatives = (scanResult['relatives'] as List?)?.cast<String>() ?? [];
      if (uris.isEmpty) {
        setState(() => _result = '文件夹为空');
        return;
      }

      final items = <_UploadItem>[];
      for (int i = 0; i < uris.length; i++) {
        final rel = i < relatives.length ? relatives[i] : 'file_$i';
        items.add(_UploadItem(localPath: uris[i], relativePath: '$folderName/$rel', safUri: uris[i]));
      }

      setState(() {
        _files = items;
        _isFolderUpload = true;
        _cacheDirPath = null;
        _result = null;
      });

    } on PlatformException catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, '选择文件夹失败: ${e.code}\n${e.message}\n${e.details}', isError: true, duration: const Duration(seconds: 8));
      }
    } catch (e) {
      if (mounted) {
        showCopyableSnackBar(context, '选择文件夹异常: $e', isError: true, duration: const Duration(seconds: 8));
      }
    }
  }

  Future<void> _pickFolderFallback() async {
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
    _autoSelectUploadsDir();
  }

  Future<Map<String, dynamic>?> _showCopyProgressDialog(String folderName) async {
    _copyProgress.value = '';
    _copyCancelled = false;
    NavigatorState? dialogNav;

    _progressChannel.setMethodCallHandler((call) async {
      if (call.method == 'onCopyProgress' && mounted) {
        final progress = (call.arguments['progress'] as num?)?.toDouble() ?? -1;
        if (progress >= 1.0) {
          _progressChannel.setMethodCallHandler(null);
          dialogNav?.pop();
        } else {
          _copyProgress.value = call.arguments['current'] as String? ?? '';
        }
      }
    });

    final future = _safChannel.invokeMethod('startCopy');

    if (!mounted) return null;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogNav = Navigator.of(ctx);
        return AlertDialog(
          title: Text('准备「$folderName」'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              ValueListenableBuilder<String>(
                valueListenable: _copyProgress,
                builder: (_, current, __) => Text(
                  current.isNotEmpty ? current : '正在扫描文件…',
                  style: const TextStyle(fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _copyCancelled = true;
                _safChannel.invokeMethod('cancelCopy');
                Navigator.pop(ctx);
              },
              child: const Text('取消', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    _progressChannel.setMethodCallHandler(null);

    try {
      final result = await future as Map<String, dynamic>?;
      if (_copyCancelled) return {'cancelled': true};
      return result;
    } catch (_) {
      return _copyCancelled ? {'cancelled': true} : null;
    }
  }

  void _clearUploadCache() {
    if (_cacheDirPath != null) {
      try {
        Directory(_cacheDirPath!).deleteSync(recursive: true);
      } catch (_) {}
      _cacheDirPath = null;
    }
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
        showCopyableSnackBar(context, '创建失败: $e', isError: true);
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
        if (file.safUri != null) {
          final bytes = await _safChannel.invokeMethod('readSafBytes', file.safUri) as Uint8List;
          await widget.api.uploadBytes(
            _selectedSharePath!,
            bytes,
            relativePath,
            (sent, total) {
              if (total > 0) setState(() => _fileProgress = sent / total);
            },
          );
        } else {
          await widget.api.uploadFile(
            _selectedSharePath!,
            file.localPath,
            relativePath,
            (sent, total) {
              if (total > 0) setState(() => _fileProgress = sent / total);
            },
          );
        }
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
    _clearUploadCache();
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
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _files.length,
                  itemBuilder: (ctx, i) {
                    final name = _files[i].relativePath.split('/').last;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
            // 目标目录（固定为上传目录）
            InputDecorator(
              decoration: const InputDecoration(
                labelText: '目标目录',
                border: OutlineInputBorder(),
              ),
              child: Text(
                _selectedSharePath != null
                    ? (_shares
                            .where((s) => s['path'] == _selectedSharePath)
                            .map((s) => s['name'] as String?)
                            .firstOrNull ??
                        _selectedSharePath!)
                    : '加载中…',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
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
