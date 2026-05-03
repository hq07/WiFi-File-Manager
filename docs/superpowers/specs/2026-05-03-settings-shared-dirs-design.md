# Settings & Shared Directories Management

## Overview

Add a settings screen to the Android app that lets users manage shared directories (add/remove/toggle visibility) directly from the phone. Add server APIs for directory browsing and common paths.

## Requirements

1. Home screen "Shared Directories" text → "共享文件夹"
2. Settings gear icon in AppBar → opens SettingsScreen
3. SettingsScreen: list all shared dirs with visibility toggle and delete
4. "Add folder" flow: common paths → directory browser → confirm share
5. `shared_dirs` entries gain a `visible` field (default true); home screen filters by it

## Server Changes

### config.py

- `shared_dirs` items gain `visible: bool` field (default `true`)
- `_load`: if `visible` key missing, default to `true` (backward compatible)
- `_save`: include `visible` in serialized output
- `add_shared_dir`: accept optional `visible` param, default `true`

### models.py

- `ShareItem` gains `visible: bool = True`

### main.py

**`GET /api/shares`** — unchanged except response now includes `visible`.

**`PATCH /api/shares/{share_id}`**
- Body: `{"visible": true/false}`
- Returns updated ShareItem
- 404 if share_id not found

**`GET /api/common-paths`**
- Returns list of well-known directories that exist on the server:
  - `~` (home), `~/Desktop`, `~/Documents`, `~/Downloads`, `~/Pictures`, `~/Movies`, `~/Music`
  - `/Volumes` (external drives)
- Each item: `{"name": str, "path": str}`
- Filter out paths that don't exist
- Requires auth

**`GET /api/browse?path=xxx`**
- Lists immediate subdirectories of `path`
- Returns `{"path": str, "dirs": [str]}`
- Only directories, sorted alphabetically
- `path` must be within a shared dir OR be the root `/` OR be a common path's parent (to allow browsing from common paths into subdirs)
- Actually: allow browsing any absolute path (the user is authenticated; they're choosing what to share). Restricting defeats the purpose.
- Requires auth

## Client Changes

### api_service.dart

- `toggleShareVisible(String id, bool visible)` — PATCH /api/shares/{id}
- `getCommonPaths()` — GET /api/common-paths
- `browsePath(String path)` — GET /api/browse?path=xxx

### home_screen.dart

- "Shared Directories" → "共享文件夹"
- Filter shares by `visible == true` before display
- Add gear IconButton in AppBar actions (before refresh and logout)

### settings_screen.dart (new)

State: loads all shares (unfiltered), common paths for add flow.

**Body — shared dirs list:**
- Each ListTile: folder icon, name, path, Switch for visible, IconButton (delete) with confirmation dialog
- Switch toggle calls `toggleShareVisible`, updates local state
- Delete calls `removeShare` with confirmation dialog

**FAB or bottom button — "添加文件夹":**
- Opens a dialog/bottom sheet with:
  - Common paths as quick-select chips/list tiles
  - "手动输入路径" text field + confirm button
- Selecting a common path opens the directory browser

### browse_screen.dart (new)

- Receives initial path
- AppBar shows current path
- Body: ListView of subdirectory names; tap navigates deeper
- Loading indicator while fetching
- Bottom bar: "选择此文件夹" button → calls `addShare`, pops back to settings
- Back button navigates up one level

## Data Flow

```
Home screen load:
  GET /api/shares → filter visible==true → display

Settings screen load:
  GET /api/shares → display all with toggles

Add folder:
  GET /api/common-paths → show quick list
  User taps common path → GET /api/browse?path=... → show subdirs
  User navigates and taps "选择此文件夹" → POST /api/shares
  Refresh settings list

Toggle visible:
  PATCH /api/shares/{id} {visible: bool} → update local state

Delete:
  DELETE /api/shares/{id} → remove from local state
```
