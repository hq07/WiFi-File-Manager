// android/lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/layout_prefs.dart';
import '../services/history_service.dart';
import '../services/favorites_service.dart';
import '../services/playback_state.dart';
import '../utils/format_utils.dart';
import 'file_list_screen.dart';
import 'upload_screen.dart';
import 'settings_screen.dart';
import 'favorites_page.dart';
import 'history_page.dart';
import 'search_screen.dart';
import 'disk_page.dart';
import 'widgets/mini_player.dart';

class HomeScreen extends StatefulWidget {
  final ApiService api;
  final LayoutPrefs layoutPrefs;
  final HistoryService historyService;
  final FavoritesService favoritesService;
  final SharedPreferences prefs;
  const HomeScreen({
    super.key,
    required this.api,
    required this.layoutPrefs,
    required this.historyService,
    required this.favoritesService,
    required this.prefs,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
  final ValueNotifier<int> _historyRefresh = ValueNotifier(0);

  @override
  void dispose() {
    _historyRefresh.dispose();
    super.dispose();
  }

  void _openDir(String path, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileListScreen(
          api: widget.api,
          layoutPrefs: widget.layoutPrefs,
          historyService: widget.historyService,
          favoritesService: widget.favoritesService,
          path: path,
          title: name,
          historyRefresh: _historyRefresh,
        ),
      ),
    ).then((_) => _historyRefresh.value++);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _HomeTab(
        api: widget.api,
        layoutPrefs: widget.layoutPrefs,
        onOpenDir: _openDir,
      ),
      FavoritesPage(
        api: widget.api,
        layoutPrefs: widget.layoutPrefs,
        historyService: widget.historyService,
        favoritesService: widget.favoritesService,
        historyRefresh: _historyRefresh,
      ),
      HistoryPage(
        api: widget.api,
        historyService: widget.historyService,
        historyRefresh: _historyRefresh,
      ),
      DiskPage(
        api: widget.api,
        onOpenDisk: _openDir,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi File Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SearchScreen(
                  api: widget.api,
                  layoutPrefs: widget.layoutPrefs,
                  historyService: widget.historyService,
                  favoritesService: widget.favoritesService,
                  historyRefresh: _historyRefresh,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    api: widget.api,
                    layoutPrefs: widget.layoutPrefs,
                    historyService: widget.historyService,
                    favoritesService: widget.favoritesService,
                    prefs: widget.prefs,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => UploadScreen(api: widget.api)),
        ),
        child: const Icon(Icons.upload_file),
      ),
      body: Column(
        children: [
          Expanded(child: pages[_currentTab]),
          ListenableBuilder(
            listenable: playbackStateNotifier,
            builder: (context, _) {
              if (playbackStateNotifier.isActive) {
                return MiniPlayer(api: widget.api);
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (i) => setState(() => _currentTab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.star_border), selectedIcon: Icon(Icons.star), label: '收藏'),
          NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history), label: '历史'),
          NavigationDestination(icon: Icon(Icons.storage_outlined), selectedIcon: Icon(Icons.storage), label: '磁盘'),
        ],
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  final ApiService api;
  final LayoutPrefs layoutPrefs;
  final void Function(String path, String name) onOpenDir;

  const _HomeTab({
    required this.api,
    required this.layoutPrefs,
    required this.onOpenDir,
  });

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
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
      setState(() {
        _shares = shares;
        _disks = disks;
        _uploadsDir = uploadsDir;
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        children: [
          if (_uploadsDir != null) ...[
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('上传文件夹', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload, color: Colors.green),
              title: Text(_uploadsDir!['name'] ?? '上传文件夹'),
              subtitle: Text(_uploadsDir!['path'] ?? ''),
              onTap: () => widget.onOpenDir(
                _uploadsDir!['path'],
                _uploadsDir!['name'] ?? '上传文件夹',
              ),
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
                onTap: () => widget.onOpenDir(s['path'], s['name'] ?? s['path']),
              )),
            ];
          }(),
          if (_disks.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('磁盘', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ..._disks.map((d) => ListTile(
              leading: const Icon(Icons.usb, color: Colors.blue),
              title: Text(d['name']),
              subtitle: Text('${formatSize(d['free'])} 可用 / ${formatSize(d['total'])}'),
              onTap: () => widget.onOpenDir(d['path'], d['name']),
            )),
          ],
          if (_shares.where((s) => s['path'] != _uploadsDir?['path'] && s['visible'] != false).isEmpty &&
              _disks.isEmpty &&
              _uploadsDir == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('没有共享文件夹或磁盘。\n请在设置中添加共享目录。', textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }
}
