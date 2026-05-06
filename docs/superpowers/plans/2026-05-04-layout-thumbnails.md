# 文件列表布局与缩略图 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在文件列表页面新增列表/网格双布局切换，支持缩略图显示，并在设置页提供布局配置选项。

**Architecture:** 服务端扩展 `FileItem` 模型增加 `duration`/`resolution` 字段，客户端新增 `LayoutPrefs` 封装 SharedPreferences 持久化设置，`FileListScreen` 支持列表/网格双布局，`SettingsScreen` 增加布局配置区域。

**Tech Stack:** Python/FastAPI (server), Flutter/Dart (client), SharedPreferences (persistence), PIL/ffprobe (metadata extraction)

---

## 文件清单

| 文件 | 操作 | 职责 |
|------|------|------|
| `server/models.py` | 修改 | FileItem 增加 duration/resolution |
| `server/file_manager.py` | 修改 | list_files 提取元数据 |
| `android/pubspec.yaml` | 修改 | 添加 shared_preferences 依赖 |
| `android/lib/services/layout_prefs.dart` | 新建 | 封装布局设置读写 |
| `android/lib/screens/file_list_screen.dart` | 修改 | 双布局 + 缩略图 + 元数据 |
| `android/lib/screens/settings_screen.dart` | 修改 | 布局设置区域 |

---

### Task 1: 服务端 — 扩展 FileItem 模型

**Files:**
- Modify: `server/models.py:30-34`

- [ ] **Step 1: 修改 FileItem 模型**

在 `server/models.py` 中给 `FileItem` 增加两个可选字段：

```python
class FileItem(BaseModel):
    name: str
    type: str  # "file" or "folder"
    size: int
    modified: str
    duration: float | None = None    # 秒，音视频文件
    resolution: str | None = None    # "1920x1080"，图片/视频文件
```

- [ ] **Step 2: 验证语法**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && python -c "from server.models import FileItem; print(FileItem(name='a', type='file', size=1, modified='t').model_dump())"`
Expected: dict with duration=None, resolution=None

- [ ] **Step 3: Commit**

```bash
git add server/models.py
git commit -m "feat: add duration/resolution fields to FileItem model"
```

---

### Task 2: 服务端 — list_files 提取元数据

**Files:**
- Modify: `server/file_manager.py:1-18`

- [ ] **Step 1: 添加元数据提取函数**

在 `server/file_manager.py` 顶部添加 import，底部添加辅助函数：

```python
import os
import platform
import subprocess
import json
from datetime import datetime, timezone

IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tiff', '.heic'}
VIDEO_EXTS = {'.mp4', '.avi', '.mkv', '.mov', '.webm', '.flv', '.wmv'}
AUDIO_EXTS = {'.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.wma'}
MEDIA_EXTS = IMAGE_EXTS | VIDEO_EXTS | AUDIO_EXTS


def _get_media_metadata(path: str, ext: str) -> dict:
    """Extract duration and/or resolution for media files. Returns {} on failure."""
    meta = {}
    try:
        if ext in IMAGE_EXTS:
            from PIL import Image
            with Image.open(path) as img:
                meta['resolution'] = f"{img.width}x{img.height}"
        elif ext in VIDEO_EXTS | AUDIO_EXTS:
            result = subprocess.run(
                ['ffprobe', '-v', 'quiet', '-print_format', 'json',
                 '-show_format', '-show_streams', path],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                info = json.loads(result.stdout)
                if 'format' in info and 'duration' in info['format']:
                    meta['duration'] = float(info['format']['duration'])
                for stream in info.get('streams', []):
                    if stream.get('codec_type') == 'video' and 'width' in stream:
                        meta['resolution'] = f"{stream['width']}x{stream['height']}"
                        break
    except Exception:
        pass
    return meta
```

- [ ] **Step 2: 修改 list_files 调用元数据提取**

替换 `list_files` 函数：

```python
def list_files(directory: str) -> list[dict]:
    items = []
    for name in sorted(os.listdir(directory)):
        full_path = os.path.join(directory, name)
        stat = os.stat(full_path)
        item = {
            "name": name,
            "type": "folder" if os.path.isdir(full_path) else "file",
            "size": stat.st_size,
            "modified": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(),
        }
        if item["type"] == "file":
            ext = os.path.splitext(name)[1].lower()
            if ext in MEDIA_EXTS and stat.st_size < 500 * 1024 * 1024:
                meta = _get_media_metadata(full_path, ext)
                item.update(meta)
        items.append(item)
    return items
```

- [ ] **Step 3: 验证语法**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && python -c "from server.file_manager import list_files; print('OK')"`
Expected: OK

- [ ] **Step 4: Commit**

```bash
git add server/file_manager.py
git commit -m "feat: extract duration/resolution metadata in list_files"
```

---

### Task 3: 客户端 — 添加 shared_preferences 依赖

**Files:**
- Modify: `android/pubspec.yaml:30-44`

- [ ] **Step 1: 在 dependencies 中添加 shared_preferences**

在 `android/pubspec.yaml` 的 `dependencies` 部分，`collection: ^1.19.0` 后面添加：

```yaml
  shared_preferences: ^2.2.0
```

- [ ] **Step 2: 安装依赖**

Run: `cd /Users/hq/python/code/WiFi-File-Manager/android && flutter pub get`
Expected: exit 0, shared_preferences in package config

- [ ] **Step 3: Commit**

```bash
git add android/pubspec.yaml android/pubspec.lock
git commit -m "feat: add shared_preferences dependency"
```

---

### Task 4: 客户端 — 创建 LayoutPrefs

**Files:**
- Create: `android/lib/services/layout_prefs.dart`

- [ ] **Step 1: 创建 layout_prefs.dart**

```dart
// android/lib/services/layout_prefs.dart
import 'package:shared_preferences/shared_preferences.dart';

enum LayoutMode { list, grid }

class LayoutPrefs {
  static const _keyLayoutMode = 'layout_mode';
  static const _keyShowThumbnails = 'show_thumbnails';
  static const _keyGridColumns = 'grid_columns';
  static const _keyShowSize = 'show_size';
  static const _keyShowDate = 'show_date';
  static const _keyShowExtension = 'show_extension';
  static const _keyShowDuration = 'show_duration';
  static const _keyShowResolution = 'show_resolution';

  late final SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  LayoutMode get layoutMode =>
      _prefs.getString(_keyLayoutMode) == 'grid' ? LayoutMode.grid : LayoutMode.list;

  set layoutMode(LayoutMode v) =>
      _prefs.setString(_keyLayoutMode, v == LayoutMode.grid ? 'grid' : 'list');

  bool get showThumbnails => _prefs.getBool(_keyShowThumbnails) ?? true;
  set showThumbnails(bool v) => _prefs.setBool(_keyShowThumbnails, v);

  int get gridColumns => _prefs.getInt(_keyGridColumns) ?? 3;
  set gridColumns(int v) => _prefs.setInt(_keyGridColumns, v);

  bool get showSize => _prefs.getBool(_keyShowSize) ?? true;
  set showSize(bool v) => _prefs.setBool(_keyShowSize, v);

  bool get showDate => _prefs.getBool(_keyShowDate) ?? true;
  set showDate(bool v) => _prefs.setBool(_keyShowDate, v);

  bool get showExtension => _prefs.getBool(_keyShowExtension) ?? false;
  set showExtension(bool v) => _prefs.setBool(_keyShowExtension, v);

  bool get showDuration => _prefs.getBool(_keyShowDuration) ?? true;
  set showDuration(bool v) => _prefs.setBool(_keyShowDuration, v);

  bool get showResolution => _prefs.getBool(_keyShowResolution) ?? true;
  set showResolution(bool v) => _prefs.setBool(_keyShowResolution, v);
}
```

- [ ] **Step 2: 验证语法**

Run: `cd /Users/hq/python/code/WiFi-File-Manager/android && dart analyze lib/services/layout_prefs.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add android/lib/services/layout_prefs.dart
git commit -m "feat: add LayoutPrefs for layout settings persistence"
```

---

### Task 5: 客户端 — FileListScreen 双布局 + 缩略图

**Files:**
- Modify: `android/lib/screens/file_list_screen.dart`

- [ ] **Step 1: 添加 import 和 LayoutPrefs 注入**

修改 `file_list_screen.dart` 的 import 和构造函数：

```dart
// android/lib/screens/file_list_screen.dart
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../services/layout_prefs.dart';
import '../utils/format_utils.dart';
import 'media_player_screen.dart';

class FileListScreen extends StatefulWidget {
  final ApiService api;
  final LayoutPrefs layoutPrefs;
  final String path;
  final String title;
  const FileListScreen({super.key, required this.api, required this.layoutPrefs, required this.path, required this.title});
```

- [ ] **Step 2: 添加布局状态和切换方法**

在 `_FileListScreenState` 类中，`_items` 声明后添加：

```dart
  List<dynamic> _items = [];
  bool _loading = true;
  late String _currentPath;
  late LayoutMode _layoutMode;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.path;
    _layoutMode = widget.layoutPrefs.layoutMode;
    _loadFiles();
  }

  void _toggleLayout() {
    setState(() {
      _layoutMode = _layoutMode == LayoutMode.list ? LayoutMode.grid : LayoutMode.list;
      widget.layoutPrefs.layoutMode = _layoutMode;
    });
  }
```

- [ ] **Step 3: 添加缩略图和元数据构建方法**

在 `_getIcon` 方法后添加：

```dart
  Widget _buildThumbnail(Map<String, dynamic> item) {
    if (item['type'] == 'folder') {
      return const Icon(Icons.folder, color: Colors.amber, size: 40);
    }
    final name = item['name'] as String;
    final ext = name.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
    if (isImage && widget.layoutPrefs.showThumbnails) {
      final filePath = '$_currentPath/$name';
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          widget.api.getPreviewUrl(filePath),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(_getIcon(item['type'], name), size: 40),
        ),
      );
    }
    return Icon(_getIcon(item['type'], name), size: 40);
  }

  Widget _buildGridThumbnail(Map<String, dynamic> item) {
    if (item['type'] == 'folder') {
      return Container(
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: Icon(Icons.folder, color: Colors.amber, size: 48)),
      );
    }
    final name = item['name'] as String;
    final ext = name.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
    if (isImage && widget.layoutPrefs.showThumbnails) {
      final filePath = '$_currentPath/$name';
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          widget.api.getPreviewUrl(filePath),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Center(child: Icon(_getIcon(item['type'], name), size: 40)),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(child: Icon(_getIcon(item['type'], name), size: 40)),
    );
  }

  String _buildMetaLine(Map<String, dynamic> item) {
    if (item['type'] == 'folder') return '';
    final prefs = widget.layoutPrefs;
    final parts = <String>[];
    if (prefs.showSize) parts.add(formatSize(item['size']));
    if (prefs.showDuration && item['duration'] != null) {
      final dur = (item['duration'] as num).toDouble();
      final min = dur ~/ 60;
      final sec = (dur % 60).toInt();
      parts.add('${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}');
    }
    if (prefs.showResolution && item['resolution'] != null) {
      parts.add(item['resolution']);
    }
    if (prefs.showExtension) {
      final ext = (item['name'] as String).split('.').last.toLowerCase();
      parts.add(ext.toUpperCase());
    }
    if (prefs.showDate && item['modified'] != null) {
      final date = DateTime.tryParse(item['modified']);
      if (date != null) {
        parts.add('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}');
      }
    }
    return parts.join(' · ');
  }
```

- [ ] **Step 4: 替换 AppBar 添加切换按钮**

修改 `build` 方法中的 `AppBar`：

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(_layoutMode == LayoutMode.list ? Icons.grid_view : Icons.view_list),
            onPressed: _toggleLayout,
          ),
        ],
      ),
```

- [ ] **Step 5: 替换 body 为双布局**

替换 `_loading` 三元表达式后的整个 body 部分：

```dart
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadFiles,
              child: _items.isEmpty
                  ? const Center(child: Text('Empty directory'))
                  : _layoutMode == LayoutMode.list
                      ? _buildListView()
                      : _buildGridView(),
            ),
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final item = _items[i];
        final metaLine = _buildMetaLine(item);
        return ListTile(
          leading: _buildThumbnail(item),
          title: Text(item['name']),
          subtitle: metaLine.isNotEmpty ? Text(metaLine, style: const TextStyle(fontSize: 12)) : null,
          onTap: () => _onItemTap(item),
          onLongPress: () => _onItemLongPress(item),
        );
      },
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.layoutPrefs.gridColumns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.8,
      ),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final item = _items[i];
        final metaLine = _buildMetaLine(item);
        return GestureDetector(
          onTap: () => _onItemTap(item),
          onLongPress: () => _onItemLongPress(item),
          child: Column(
            children: [
              Expanded(child: _buildGridThumbnail(item)),
              const SizedBox(height: 4),
              Text(
                item['name'],
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              if (metaLine.isNotEmpty)
                Text(
                  metaLine,
                  style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        );
      },
    );
  }
```

- [ ] **Step 6: 更新所有 FileListScreen 的 Navigator.push 调用**

在 `file_list_screen.dart` 中，`_onItemTap` 里跳转子目录时需要传递 `layoutPrefs`：

```dart
  void _onItemTap(Map<String, dynamic> item) {
    if (item['type'] == 'folder') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FileListScreen(
            api: widget.api,
            layoutPrefs: widget.layoutPrefs,
            path: '$_currentPath/${item['name']}',
            title: item['name'],
          ),
        ),
      );
    }
    // ... rest unchanged
```

- [ ] **Step 7: Commit**

```bash
git add android/lib/screens/file_list_screen.dart
git commit -m "feat: add list/grid dual layout with thumbnails to FileListScreen"
```

---

### Task 6: 客户端 — HomeScreen 传递 layoutPrefs

**Files:**
- Modify: `android/lib/screens/home_screen.dart`

- [ ] **Step 1: 添加 import 和字段**

在 `home_screen.dart` 中：

```dart
import '../services/layout_prefs.dart';

class HomeScreen extends StatefulWidget {
  final ApiService api;
  final LayoutPrefs layoutPrefs;
  const HomeScreen({super.key, required this.api, required this.layoutPrefs});
```

- [ ] **Step 2: 更新 _openDir 调用**

```dart
  void _openDir(String path, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileListScreen(api: widget.api, layoutPrefs: widget.layoutPrefs, path: path, title: name),
      ),
    );
  }
```

- [ ] **Step 3: 更新 SettingsScreen 调用**

在 `home_screen.dart` 中跳转 `SettingsScreen` 时传递 `layoutPrefs`：

```dart
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(api: widget.api, layoutPrefs: widget.layoutPrefs),
                ),
              );
              _loadData();
            },
          ),
```

- [ ] **Step 4: Commit**

```bash
git add android/lib/screens/home_screen.dart
git commit -m "feat: pass LayoutPrefs through HomeScreen to FileListScreen"
```

---

### Task 7: 客户端 — main.dart 初始化 LayoutPrefs

**Files:**
- Modify: `android/lib/main.dart`

- [ ] **Step 1: 修改 main.dart 初始化 LayoutPrefs**

在 `main.dart` 中，确保 `LayoutPrefs` 在 app 启动时初始化，然后传递给 `HomeScreen`。具体修改取决于 main.dart 当前结构，核心是：

1. 在 `main()` 中 `WidgetsFlutterBinding.ensureInitialized()`
2. 创建 `LayoutPrefs` 实例并调用 `await init()`
3. 将 `layoutPrefs` 传递给 `HomeScreen`

- [ ] **Step 2: Commit**

```bash
git add android/lib/main.dart
git commit -m "feat: initialize LayoutPrefs in main.dart"
```

---

### Task 8: 客户端 — SettingsScreen 布局设置区域

**Files:**
- Modify: `android/lib/screens/settings_screen.dart`

- [ ] **Step 1: 添加 import 和构造函数参数**

```dart
import '../services/layout_prefs.dart';

class SettingsScreen extends StatefulWidget {
  final ApiService api;
  final LayoutPrefs layoutPrefs;
  const SettingsScreen({super.key, required this.api, required this.layoutPrefs});
```

- [ ] **Step 2: 在 body 的 ListView 中，`_shares` 列表之前添加布局设置区域**

在 `ListView` 的 `children` 开头添加：

```dart
                  // 布局设置
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text('显示布局', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  // 默认布局
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
                  // 显示缩略图
                  SwitchListTile(
                    title: const Text('显示缩略图'),
                    subtitle: const Text('图片文件显示真实预览'),
                    value: widget.layoutPrefs.showThumbnails,
                    onChanged: (v) => setState(() => widget.layoutPrefs.showThumbnails = v),
                  ),
                  // 网格列数
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
```

- [ ] **Step 3: Commit**

```bash
git add android/lib/screens/settings_screen.dart
git commit -m "feat: add layout settings section to SettingsScreen"
```

---

### Task 9: 构建验证

- [ ] **Step 1: 服务端语法检查**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && python -c "from server.main import app; print('Server OK')"`

- [ ] **Step 2: 客户端分析**

Run: `cd /Users/hq/python/code/WiFi-File-Manager/android && flutter analyze`
Expected: No errors (warnings acceptable)

- [ ] **Step 3: 构建 APK**

Run: `cd /Users/hq/python/code/WiFi-File-Manager/android && flutter build apk --release`
Expected: ✓ Built app-release.apk

- [ ] **Step 4: 最终 Commit**

```bash
git add -A
git commit -m "feat: complete layout toggle, thumbnails, and metadata display"
```
