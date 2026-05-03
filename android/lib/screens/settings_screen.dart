// android/lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/layout_prefs.dart';
import 'browse_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ApiService api;
  final LayoutPrefs layoutPrefs;
  const SettingsScreen({super.key, required this.api, required this.layoutPrefs});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<dynamic> _shares = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadShares();
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
      appBar: AppBar(title: const Text('设置')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addFolder,
        icon: const Icon(Icons.add),
        label: const Text('添加文件夹'),
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
                ],
              ),
            ),
    );
  }
}
