// android/lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'browse_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ApiService api;
  const SettingsScreen({super.key, required this.api});

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
              child: _shares.isEmpty
                  ? const Center(child: Text('暂无共享目录'))
                  : ListView.builder(
                      itemCount: _shares.length,
                      itemBuilder: (context, index) {
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
                      },
                    ),
            ),
    );
  }
}
