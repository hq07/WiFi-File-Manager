// android/lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'file_list_screen.dart';
import 'login_screen.dart';
import 'upload_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiService api;
  const HomeScreen({super.key, required this.api});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _shares = [];
  List<dynamic> _disks = [];
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
      setState(() { _shares = shares; _disks = disks; _loading = false; });
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
        builder: (_) => FileListScreen(api: widget.api, path: path, title: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi File Manager'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              widget.api.clearToken();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => LoginScreen(api: widget.api),
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
                  if (_shares.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Shared Directories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    ..._shares.map((s) => ListTile(
                      leading: const Icon(Icons.folder, color: Colors.amber),
                      title: Text(s['name'] ?? s['path']),
                      subtitle: Text(s['path']),
                      onTap: () => _openDir(s['path'], s['name'] ?? s['path']),
                    )),
                  ],
                  if (_disks.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('External Disks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    ..._disks.map((d) => ListTile(
                      leading: const Icon(Icons.usb, color: Colors.blue),
                      title: Text(d['name']),
                      subtitle: Text('${_formatSize(d['free'])} free / ${_formatSize(d['total'])}'),
                      onTap: () => _openDir(d['path'], d['name']),
                    )),
                  ],
                  if (_shares.isEmpty && _disks.isEmpty)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No shared directories or disks found.\nAdd shared dirs from the server.', textAlign: TextAlign.center),
                    )),
                ],
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
