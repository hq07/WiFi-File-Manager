# Settings & Shared Directories Management — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Android users manage shared directories (add/remove/toggle visibility) from a settings screen, with a directory browser for picking paths.

**Architecture:** Server gains three new endpoints (`PATCH shares`, `GET common-paths`, `GET browse`) and a `visible` field on shares. Client gains a SettingsScreen and BrowseScreen. No new dependencies.

**Tech Stack:** Python / FastAPI / Pydantic (server), Flutter / Dart (client)

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `server/models.py` | Add `visible` to ShareItem, add PatchShareRequest |
| Modify | `server/config.py` | Backward-compatible `visible` field in shared_dirs |
| Modify | `server/main.py` | PATCH shares, GET common-paths, GET browse endpoints |
| Modify | `server/tests/test_main.py` | Tests for all new endpoints |
| Modify | `android/lib/services/api_service.dart` | New API methods |
| Modify | `android/lib/screens/home_screen.dart` | Chinese text, gear icon, visible filter |
| Create | `android/lib/screens/settings_screen.dart` | Settings list with toggles + add button |
| Create | `android/lib/screens/browse_screen.dart` | Directory browser |

---

### Task 1: Add `visible` field to server models and config

**Files:**
- Modify: `server/models.py:15-18`
- Modify: `server/config.py:22-31, 64-72`
- Modify: `server/tests/test_main.py`

- [ ] **Step 1: Update ShareItem model**

In `server/models.py`, add `visible` field:

```python
class ShareItem(BaseModel):
    id: str
    path: str
    name: str
    visible: bool = True
```

- [ ] **Step 2: Backward-compatible load in config**

In `server/config.py`, update `_load` to default `visible` to `True` when missing:

```python
def _load(self):
    if os.path.exists(self.config_path):
        with open(self.config_path, "r") as f:
            data = json.load(f)
        self.port = data.get("port", 8000)
        self.password_hash = data.get("password_hash")
        self.shared_dirs = data.get("shared_dirs", [])
        self.uploads_dir = data.get("uploads_dir", DEFAULT_UPLOAD_DIR)
        # Backfill visible field for old configs
        for d in self.shared_dirs:
            d.setdefault("visible", True)
    else:
        self._save()
```

- [ ] **Step 3: Include visible in save**

In `server/config.py`, `_save` already serializes `self.shared_dirs` which will now contain `visible`. No code change needed — verify by reading the method.

- [ ] **Step 4: Add set_visible method to Config**

In `server/config.py`, add after `remove_shared_dir`:

```python
def set_visible(self, share_id: str, visible: bool) -> bool:
    for d in self.shared_dirs:
        if d["id"] == share_id:
            d["visible"] = visible
            self._save()
            return True
    return False
```

- [ ] **Step 5: Update get_shares to include visible in response**

In `server/main.py`, update `get_shares`:

```python
@app.get("/api/shares", response_model=list[ShareItem])
def get_shares(user=Depends(get_current_user)):
    return [
        ShareItem(id=d["id"], path=d["path"], name=os.path.basename(d["path"]),
                  visible=d.get("visible", True))
        for d in config.shared_dirs
    ]
```

- [ ] **Step 6: Write test for visible field**

Append to `server/tests/test_main.py`:

```python
def test_share_visible_field():
    headers = _auth_headers()
    client = TestClient(app)
    with tempfile.TemporaryDirectory() as tmpdir:
        resp = client.post("/api/shares", json={"path": tmpdir}, headers=headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["visible"] is True

        resp = client.get("/api/shares", headers=headers)
        assert resp.json()[0]["visible"] is True
```

- [ ] **Step 7: Run tests**

```bash
cd /Users/hq/python/code/WiFi-File-Manager && python -m pytest server/tests/test_main.py -v
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add server/models.py server/config.py server/main.py server/tests/test_main.py
git commit -m "feat: add visible field to shared directories"
```

---

### Task 2: Add PATCH /api/shares/{share_id} endpoint

**Files:**
- Modify: `server/models.py`
- Modify: `server/main.py:150-169`
- Modify: `server/tests/test_main.py`

- [ ] **Step 1: Add PatchShareRequest model**

In `server/models.py`, add:

```python
class PatchShareRequest(BaseModel):
    visible: bool
```

- [ ] **Step 2: Add PATCH endpoint**

In `server/main.py`, add after the DELETE `/api/shares/{share_id}` endpoint:

```python
@app.patch("/api/shares/{share_id}", response_model=ShareItem)
def update_share(share_id: str, req: PatchShareRequest, user=Depends(get_current_user)):
    if not config.set_visible(share_id, req.visible):
        raise HTTPException(status_code=404, detail="Share not found")
    d = next(d for d in config.shared_dirs if d["id"] == share_id)
    return ShareItem(id=d["id"], path=d["path"], name=os.path.basename(d["path"]),
                     visible=d.get("visible", True))
```

- [ ] **Step 3: Write tests**

Append to `server/tests/test_main.py`:

```python
def test_patch_share_visible():
    headers = _auth_headers()
    client = TestClient(app)
    with tempfile.TemporaryDirectory() as tmpdir:
        resp = client.post("/api/shares", json={"path": tmpdir}, headers=headers)
        share_id = resp.json()["id"]

        resp = client.patch(f"/api/shares/{share_id}", json={"visible": False}, headers=headers)
        assert resp.status_code == 200
        assert resp.json()["visible"] is False

        resp = client.patch(f"/api/shares/{share_id}", json={"visible": True}, headers=headers)
        assert resp.status_code == 200
        assert resp.json()["visible"] is True


def test_patch_share_not_found():
    headers = _auth_headers()
    client = TestClient(app)
    resp = client.patch("/api/shares/nonexistent", json={"visible": False}, headers=headers)
    assert resp.status_code == 404
```

- [ ] **Step 4: Run tests**

```bash
cd /Users/hq/python/code/WiFi-File-Manager && python -m pytest server/tests/test_main.py -v
```

- [ ] **Step 5: Commit**

```bash
git add server/models.py server/main.py server/tests/test_main.py
git commit -m "feat: add PATCH /api/shares endpoint for visibility toggle"
```

---

### Task 3: Add GET /api/common-paths endpoint

**Files:**
- Modify: `server/main.py`
- Modify: `server/tests/test_main.py`

- [ ] **Step 1: Implement endpoint**

In `server/main.py`, add after the `get_uploads_dir` endpoint:

```python
@app.get("/api/common-paths")
def get_common_paths(user=Depends(get_current_user)):
    home = os.path.expanduser("~")
    candidates = [
        ("用户目录", home),
        ("桌面", os.path.join(home, "Desktop")),
        ("文稿", os.path.join(home, "Documents")),
        ("下载", os.path.join(home, "Downloads")),
        ("图片", os.path.join(home, "Pictures")),
        ("影片", os.path.join(home, "Movies")),
        ("音乐", os.path.join(home, "Music")),
        ("外置磁盘", "/Volumes"),
    ]
    return [{"name": name, "path": path} for name, path in candidates if os.path.isdir(path)]
```

- [ ] **Step 2: Write test**

Append to `server/tests/test_main.py`:

```python
def test_common_paths():
    headers = _auth_headers()
    client = TestClient(app)
    resp = client.get("/api/common-paths", headers=headers)
    assert resp.status_code == 200
    paths = resp.json()
    assert isinstance(paths, list)
    assert all("name" in p and "path" in p for p in paths)
    # Home dir should always exist
    home = os.path.expanduser("~")
    assert any(p["path"] == home for p in paths)
```

- [ ] **Step 3: Run tests**

```bash
cd /Users/hq/python/code/WiFi-File-Manager && python -m pytest server/tests/test_main.py -v
```

- [ ] **Step 4: Commit**

```bash
git add server/main.py server/tests/test_main.py
git commit -m "feat: add GET /api/common-paths endpoint"
```

---

### Task 4: Add GET /api/browse endpoint

**Files:**
- Modify: `server/main.py`
- Modify: `server/tests/test_main.py`

- [ ] **Step 1: Implement endpoint**

In `server/main.py`, add after `get_common_paths`:

```python
@app.get("/api/browse")
def browse_dirs(path: str, user=Depends(get_current_user)):
    if not os.path.isdir(path):
        raise HTTPException(status_code=404, detail="Directory not found")
    try:
        entries = sorted(
            e for e in os.listdir(path)
            if os.path.isdir(os.path.join(path, e)) and not e.startswith(".")
        )
    except PermissionError:
        raise HTTPException(status_code=403, detail="Permission denied")
    return {"path": path, "dirs": entries}
```

- [ ] **Step 2: Write tests**

Append to `server/tests/test_main.py`:

```python
def test_browse_dirs():
    headers = _auth_headers()
    client = TestClient(app)
    with tempfile.TemporaryDirectory() as tmpdir:
        os.makedirs(os.path.join(tmpdir, "alpha"))
        os.makedirs(os.path.join(tmpdir, "beta"))
        with open(os.path.join(tmpdir, "file.txt"), "w") as f:
            f.write("hi")
        os.makedirs(os.path.join(tmpdir, ".hidden"))

        resp = client.get("/api/browse", params={"path": tmpdir}, headers=headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["path"] == tmpdir
        assert data["dirs"] == ["alpha", "beta"]  # sorted, no files, no hidden


def test_browse_not_found():
    headers = _auth_headers()
    client = TestClient(app)
    resp = client.get("/api/browse", params={"path": "/nonexistent"}, headers=headers)
    assert resp.status_code == 404
```

- [ ] **Step 3: Run tests**

```bash
cd /Users/hq/python/code/WiFi-File-Manager && python -m pytest server/tests/test_main.py -v
```

- [ ] **Step 4: Commit**

```bash
git add server/main.py server/tests/test_main.py
git commit -m "feat: add GET /api/browse endpoint for directory listing"
```

---

### Task 5: Update Android ApiService

**Files:**
- Modify: `android/lib/services/api_service.dart:53-67`

- [ ] **Step 1: Add new methods**

Append to `ApiService` class, after the `renameFile` method:

```dart
  Future<void> toggleShareVisible(String id, bool visible) async {
    await _dio.patch('$_baseUrl/api/shares/$id',
        data: {'visible': visible}, options: _authOptions);
  }

  Future<List<dynamic>> getCommonPaths() async {
    final resp =
        await _dio.get('$_baseUrl/api/common-paths', options: _authOptions);
    return resp.data;
  }

  Future<Map<String, dynamic>> browsePath(String path) async {
    final resp = await _dio.get('$_baseUrl/api/browse',
        queryParameters: {'path': path}, options: _authOptions);
    return resp.data;
  }
```

- [ ] **Step 2: Commit**

```bash
git add android/lib/services/api_service.dart
git commit -m "feat: add toggleShareVisible, getCommonPaths, browsePath to ApiService"
```

---

### Task 6: Update HomeScreen — Chinese text and gear icon

**Files:**
- Modify: `android/lib/screens/home_screen.dart:1-6, 56-74, 100-115`

- [ ] **Step 1: Add import for SettingsScreen**

At the top of `home_screen.dart`, add import:

```dart
import 'settings_screen.dart';
```

- [ ] **Step 2: Add gear icon to AppBar**

In the `actions` list of the AppBar, add a settings icon before refresh. Replace the `actions` block:

```dart
actions: [
  IconButton(
    icon: const Icon(Icons.settings),
    onPressed: () async {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SettingsScreen(api: widget.api),
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
          builder: (_) => LoginScreen(api: widget.api),
        ),
      );
    },
  ),
],
```

- [ ] **Step 3: Change "Shared Directories" to "共享文件夹" and filter by visible**

In the body `ListView`, replace the "Shared Directories" section. Change the text on line 106 and add visible filtering:

```dart
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
```

Also update the empty-state message from English to Chinese:

```dart
if (_shares.where((s) => s['path'] != _uploadsDir?['path'] && s['visible'] != false).isEmpty && _disks.isEmpty && _uploadsDir == null)
  const Center(child: Padding(
    padding: EdgeInsets.all(32),
    child: Text('没有共享文件夹或磁盘。\n请在设置中添加共享目录。', textAlign: TextAlign.center),
  )),
```

- [ ] **Step 4: Commit**

```bash
git add android/lib/screens/home_screen.dart
git commit -m "feat: add settings gear icon, Chinese labels, visible filter on home"
```

---

### Task 7: Create SettingsScreen

**Files:**
- Create: `android/lib/screens/settings_screen.dart`

- [ ] **Step 1: Create the file**

```dart
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
```

- [ ] **Step 2: Commit**

```bash
git add android/lib/screens/settings_screen.dart
git commit -m "feat: add SettingsScreen with visibility toggles and delete"
```

---

### Task 8: Create BrowseScreen

**Files:**
- Create: `android/lib/screens/browse_screen.dart`

- [ ] **Step 1: Create the file**

```dart
// android/lib/screens/browse_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法访问: $e')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
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
```

- [ ] **Step 2: Commit**

```bash
git add android/lib/screens/browse_screen.dart
git commit -m "feat: add BrowseScreen with common paths and directory navigation"
```

---

### Task 9: Run all server tests and verify

- [ ] **Step 1: Run full test suite**

```bash
cd /Users/hq/python/code/WiFi-File-Manager && python -m pytest server/tests/test_main.py -v
```

Expected: all tests pass (existing + new).

- [ ] **Step 2: Verify config.json still loads correctly**

```bash
cd /Users/hq/python/code/WiFi-File-Manager && python -c "from server.config import Config; c = Config(); print(c.shared_dirs)"
```

Expected: existing shared_dirs with `visible: True` backfilled.

- [ ] **Step 3: Final commit if any fixes needed**

```bash
git add -A && git commit -m "fix: address test or config issues"
```
