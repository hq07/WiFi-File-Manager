// android/lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/layout_prefs.dart';
import '../utils/format_utils.dart';
import 'file_list_screen.dart';
import 'login_screen.dart';
import 'upload_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiService api;
  final LayoutPrefs layoutPrefs;
  const HomeScreen({super.key, required this.api, required this.layoutPrefs});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _shares = [];
  List<dynamic> _disks = [];
  Map<String, dynamic>? _uploadsDir;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; });
    try {
      final shares = await widget.api.getShares();
      final disks = await widget.api.getDisks();
      final uploadsDir = await widget.api.getUploadsDir();
      setState(() { _shares = shares; _disks = disks; _uploadsDir = uploadsDir; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _openDir(String path, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileListScreen(api: widget.api, layoutPrefs: widget.layoutPrefs, path: path, title: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi File Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(api: widget.api, layoutPrefs: widget.layoutPrefs),
                ),
              );
              _loadData(); // refresh after returning from settings
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              widget.api.clearToken();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => LoginScreen(api: widget.api, layoutPrefs: widget.layoutPrefs),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UploadScreen(api: widget.api))),
        child: const Icon(Icons.upload_file),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                children: [
                  // 上传文件夹 — 始终显示
                  if (_uploadsDir != null) ...[
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('上传文件夹', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.cloud_upload, color: Colors.green),
                      title: Text(_uploadsDir!['name'] ?? '上传文件夹'),
                      subtitle: Text(_uploadsDir!['path'] ?? ''),
                      onTap: () => _openDir(_uploadsDir!['path'], _uploadsDir!['name'] ?? '上传文件夹'),
                    ),
                    const Divider(),
                  ],
                  ...() {
                    final sharedOnly = _shares
                        .where((s) => s['path'] != _uploadsDir?['path'] && s['visible'] != false)
                        .toList();
                    if (sharedOnly.isEmpty) return <Widget>[];
                    return [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('共享文件夹', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      ...sharedOnly.map((s) => ListTile(
                      leading: const Icon(Icons.folder, color: Colors.amber),
                      title: Text(s['name'] ?? s['path']),
                      subtitle: Text(s['path']),
                      onTap: () => _openDir(s['path'], s['name'] ?? s['path']),
                    )),
                    ];
                  }(),
                  if (_disks.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('External Disks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    ..._disks.map((d) => ListTile(
                      leading: const Icon(Icons.usb, color: Colors.blue),
                      title: Text(d['name']),
                      subtitle: Text('${formatSize(d['free'])} free / ${formatSize(d['total'])}'),
                      onTap: () => _openDir(d['path'], d['name']),
                    )),
                  ],
                  if (_shares.where((s) => s['path'] != _uploadsDir?['path'] && s['visible'] != false).isEmpty && _disks.isEmpty && _uploadsDir == null)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('没有共享文件夹或磁盘。\n请在设置中添加共享目录。', textAlign: TextAlign.center),
                    )),
                ],
              ),
            ),
    );
  }

}
