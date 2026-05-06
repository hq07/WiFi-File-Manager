// android/lib/screens/settings_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/layout_prefs.dart';
import '../services/history_service.dart';
import '../services/favorites_service.dart';
import '../utils/format_utils.dart';
import 'browse_screen.dart';
import 'trash_screen.dart';
import 'login_screen.dart';
import 'widgets/preview_image.dart';

class SettingsScreen extends StatefulWidget {
  final ApiService api;
  final LayoutPrefs layoutPrefs;
  final HistoryService historyService;
  final FavoritesService favoritesService;
  final SharedPreferences prefs;
  const SettingsScreen({
    super.key,
    required this.api,
    required this.layoutPrefs,
    required this.historyService,
    required this.favoritesService,
    required this.prefs,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<dynamic> _shares = [];
  bool _loading = true;
  int _serverCacheCount = 0;
  int _serverCacheSize = 0;
  int _localCacheSize = 0;

  @override
  void initState() {
    super.initState();
    _loadShares();
    _loadCacheInfo();
  }

  Future<void> _loadShares() async {
    setState(() => _loading = true);
    try {
      final shares = await widget.api.getShares();
      setState(() {
        _shares = shares;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }

  Future<void> _loadCacheInfo() async {
    try {
      final info = await widget.api.getCacheInfo();
      final localDir = await _getLocalCacheDir();
      int localSize = 0;
      if (await localDir.exists()) {
        await for (final f in localDir.list()) {
          if (f is File) localSize += await f.length();
        }
      }
      if (mounted) {
        setState(() {
          _serverCacheCount = info['count'] ?? 0;
          _serverCacheSize = info['size'] ?? 0;
          _localCacheSize = localSize;
        });
      }
    } catch (_) {}
  }

  Future<Directory> _getLocalCacheDir() async {
    final dir = await getTemporaryDirectory();
    return Directory('${dir.path}/preview_cache');
  }

  Future<void> _clearCache() async {
    try {
      await widget.api.clearServerCache();
      final localDir = await _getLocalCacheDir();
      if (await localDir.exists()) {
        await for (final f in localDir.list()) {
          if (f is File) await f.delete();
        }
      }
      PreviewImage.clearMemCache();
      setState(() {
        _serverCacheCount = 0;
        _serverCacheSize = 0;
        _localCacheSize = 0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('缓存已清除')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除失败: $e')),
        );
      }
    }
  }

  Future<void> _toggleVisible(int index, bool value) async {
    final share = _shares[index];
    try {
      await widget.api.toggleShareVisible(share['id'], value);
      setState(() => _shares[index]['visible'] = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteShare(int index) async {
    final share = _shares[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要移除共享目录「${share['name']}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.api.removeShare(share['id']);
      setState(() => _shares.removeAt(index));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<void> _addFolder() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => BrowseScreen(api: widget.api)),
    );
    if (result != null) {
      _loadShares();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          IconButton(
            onPressed: _addFolder,
            icon: const Icon(Icons.create_new_folder),
            tooltip: '添加文件夹',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadShares,
              child: ListView(
                children: [
                  // 布局设置
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text('显示布局', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Text('默认布局', style: TextStyle(fontSize: 15)),
                        const Spacer(),
                        SegmentedButton<LayoutMode>(
                          segments: const [
                            ButtonSegment(value: LayoutMode.list, label: Text('列表'), icon: Icon(Icons.view_list)),
                            ButtonSegment(value: LayoutMode.grid, label: Text('网格'), icon: Icon(Icons.grid_view)),
                          ],
                          selected: {widget.layoutPrefs.layoutMode},
                          onSelectionChanged: (v) => setState(() => widget.layoutPrefs.layoutMode = v.first),
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('显示缩略图'),
                    subtitle: const Text('图片文件显示真实预览'),
                    value: widget.layoutPrefs.showThumbnails,
                    onChanged: (v) => setState(() => widget.layoutPrefs.showThumbnails = v),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Text('网格列数', style: TextStyle(fontSize: 15)),
                        const Spacer(),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 2, label: Text('2')),
                            ButtonSegment(value: 3, label: Text('3')),
                            ButtonSegment(value: 4, label: Text('4')),
                          ],
                          selected: {widget.layoutPrefs.gridColumns},
                          onSelectionChanged: (v) => setState(() => widget.layoutPrefs.gridColumns = v.first),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('文件信息', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  SwitchListTile(
                    title: const Text('文件大小'),
                    value: widget.layoutPrefs.showSize,
                    onChanged: (v) => setState(() => widget.layoutPrefs.showSize = v),
                  ),
                  SwitchListTile(
                    title: const Text('修改日期'),
                    value: widget.layoutPrefs.showDate,
                    onChanged: (v) => setState(() => widget.layoutPrefs.showDate = v),
                  ),
                  SwitchListTile(
                    title: const Text('文件扩展名'),
                    value: widget.layoutPrefs.showExtension,
                    onChanged: (v) => setState(() => widget.layoutPrefs.showExtension = v),
                  ),
                  SwitchListTile(
                    title: const Text('时长'),
                    subtitle: const Text('音频/视频文件'),
                    value: widget.layoutPrefs.showDuration,
                    onChanged: (v) => setState(() => widget.layoutPrefs.showDuration = v),
                  ),
                  SwitchListTile(
                    title: const Text('分辨率'),
                    subtitle: const Text('图片/视频文件'),
                    value: widget.layoutPrefs.showResolution,
                    onChanged: (v) => setState(() => widget.layoutPrefs.showResolution = v),
                  ),
                  const Divider(),
                  // 缓存管理
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('缓存管理', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.storage),
                    title: const Text('缩略图缓存'),
                    subtitle: Text(
                      '服务端: ${_serverCacheCount} 个 (${formatSize(_serverCacheSize)})\n'
                      '本地: ${formatSize(_localCacheSize)}',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (_serverCacheCount > 0 || _localCacheSize > 0) ? _clearCache : null,
                        icon: const Icon(Icons.delete_sweep),
                        label: const Text('清除缓存'),
                      ),
                    ),
                  ),
                  const Divider(),
                  // 废纸篓入口
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.red),
                    title: const Text('废纸篓'),
                    subtitle: const Text('查看和管理已删除的文件'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TrashScreen(api: widget.api)),
                    ),
                  ),
                  const Divider(),
                  // 共享文件夹
                  if (_shares.isEmpty)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('暂无共享目录'),
                    ))
                  else
                    ...List.generate(_shares.length, (index) {
                      final s = _shares[index];
                      return ListTile(
                        leading: const Icon(Icons.folder, color: Colors.amber),
                        title: Text(s['name'] ?? s['path']),
                        subtitle: Text(s['path']),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: s['visible'] ?? true,
                              onChanged: (v) => _toggleVisible(index, v),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteShare(index),
                            ),
                          ],
                        ),
                      );
                    }),
                  const Divider(),
                  // 退出登录
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.logout, color: Colors.red),
                        label: const Text('退出登录', style: TextStyle(color: Colors.red, fontSize: 16)),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('退出登录'),
                              content: const Text('确定要退出登录吗？'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('确定', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            widget.api.clearToken();
                            if (mounted) {
                              Navigator.of(context).popUntil((route) => route.isFirst);
                            }
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
