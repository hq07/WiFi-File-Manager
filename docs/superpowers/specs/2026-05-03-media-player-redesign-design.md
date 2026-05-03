# Media Player Redesign — Design Spec

## Overview

Redesign the Flutter APK's `FilePreviewScreen` into a unified media player with dedicated views for video, audio, image, and text/code files. Adds gesture controls, playback speed, sleep timer, playlist management, and a polished adaptive theme.

## Architecture

**Approach**: Unified shell (`MediaPlayerScreen`) + type-specific content views in `widgets/`.

### File Structure

```
android/lib/
├── screens/
│   ├── file_list_screen.dart       # Update navigation to MediaPlayerScreen
│   ├── media_player_screen.dart    # NEW — unified shell (fullscreen, gestures, theme)
│   └── widgets/
│       ├── video_player_view.dart   # Video content + classic bottom control bar
│       ├── audio_player_view.dart   # Album art centered + dedicated audio UI
│       ├── image_gallery_view.dart  # Swipeable gallery + gestures + slideshow
│       ├── text_code_view.dart      # Syntax highlight + search + line numbers
│       ├── media_info_panel.dart    # Shared media info bottom sheet
│       ├── gesture_handler.dart     # Unified gesture detection widget
│       └── playlist_manager.dart    # Playlist state + auto-play logic
├── utils/
│   └── format_utils.dart           # Shared: formatSize, formatDuration, getLanguageName
```

### New Dependencies

| Package | Purpose |
|---------|---------|
| `highlight` + `flutter_highlight` | Syntax highlighting for code/text files |
| `wakelock_plus` | Prevent screen from sleeping during playback |
| `screen_brightness` | Gesture-based brightness control |
| `volume_controller` | Gesture-based system volume control |
| `collection` | Useful collection extensions (firstWhereOrNull, etc.) |

---

## Video Player

### Layout: Classic Bottom Control Bar

**Top bar** (auto-hides after 3s):
- Back arrow + filename (truncated)
- Info icon (ⓘ) — opens media info panel
- More menu (⋮) — playback speed, sleep timer, playlist

**Center**: Video surface (AspectRatio widget)

**Bottom control bar** (auto-hides after 3s):
- Gradient progress bar with scrub handle
- Play/pause, previous, next buttons
- Current time / total time
- Playback speed badge
- Volume icon
- Fullscreen toggle

### Gesture Controls

| Gesture | Zone | Action | Feedback |
|---------|------|--------|----------|
| Single tap | Anywhere | Toggle control bar visibility | — |
| Double tap | Left 1/3 | Rewind 10 seconds | ↺ -10s circle animation (300ms fade in, 500ms fade out) |
| Double tap | Center 1/3 | Toggle play/pause | ▶/⏸ circle animation |
| Double tap | Right 1/3 | Forward 10 seconds | ↻ +10s circle animation |
| Horizontal swipe | Anywhere | Seek forward/backward | Time preview overlay (1% screen = 2s) |
| Vertical swipe | Left half | Adjust screen brightness | Brightness icon + percentage overlay |
| Vertical swipe | Right half | Adjust system volume | Volume icon + percentage overlay |
| Pinch | Anywhere | Zoom (video only, limited) | — |

### Gesture Animation

Double-tap feedback: circular semi-transparent backdrop-blur container (64x64) with icon + text label. Fades in over 300ms, holds 500ms, fades out over 300ms.

### Screen Lock

- Lock icon visible when controls are shown
- When locked: gestures disabled, rotation locked, only unlock button responds
- Unlock: single tap shows only the unlock button

### Fullscreen

- Toggle via bottom-right icon
- Uses `SystemChrome.setEnabledSystemUIMode` to hide system bars
- Supports both portrait and landscape orientations
- Lock orientation button available

### Playback Speed

Options: 0.5x, 0.75x, 1.0x (default), 1.25x, 1.5x, 2.0x
- Displayed as a badge on the control bar (e.g., "1.0x")
- Tap to open bottom sheet selector
- Persisted in memory for the current session

### Sleep Timer

**Trigger**: Tap ⏰ icon in control bar or more menu

**Options**: 15 / 30 / 45 / 60 / 90 minutes + Cancel

**Behavior**:
1. Timer starts immediately on selection
2. ⏰ icon turns purple, shows remaining time (e.g., "⏰ 23:45")
3. Timer ends → auto-pause playback, show SnackBar: "定时关闭已触发，播放已暂停"
4. Stays on current screen (does not exit)
5. User can resume playback manually; timer is cleared

### Playlist

**Source**: All media files of the same type in the current directory, sorted by filename

**Behavior**:
- Auto-populated when opening a file
- Previous/Next buttons cycle through playlist
- When current file ends → auto-play next
- Playlist view: bottom sheet showing all files, current file highlighted

### Media Info Panel

Bottom sheet showing:
- File name
- File size (formatted)
- Resolution (from VideoPlayerController.value.size)
- Duration (from VideoPlayerController.value.duration)
- Codec info (not available from video_player; show file extension as format)

---

## Audio Player

### Layout: Album Art Centered

**Background**: Deep purple gradient (`#1a1040` → `#0f0c29`), adapts to light theme

**Top bar**: Back button, "正在播放" label, info icon + more menu

**Center**:
- Large album art placeholder (220x220, border-radius 24)
- Gradient placeholder with music note icon (no actual album art API)
- Glow effect behind art: radial gradient + blur(30px)
- Reflection highlight on top half of art

**Below art**:
- File name (large, bold)
- Format info line: e.g., "FLAC · 44.1kHz · 16bit · 35.2 MB"

**Progress bar**: Gradient bar with white circular thumb, current/total time below

**Main controls**:
- Shuffle, Previous, Play/Pause (large gradient button), Next, Repeat (off/all/one cycle)

**Bottom bar**: Speed badge, volume slider, playlist button, sleep timer

### Sleep Timer

Same implementation as video — shared `SleepTimerManager` class.

### Playlist

Same as video — shared `PlaylistManager` class, filtered to audio files.

---

## Image Viewer

### Layout

**Top bar** (auto-hides): Back, filename, share icon, info icon, more menu

**Center**: PageView with PhotoView for each image

**Page indicator**: Centered pill showing "3 / 12"

**Bottom bar** (auto-hides): Share, Download

### Gesture Controls

| Gesture | Action |
|---------|--------|
| Single tap | Toggle top/bottom bars |
| Double tap | Quick zoom in / restore original scale |
| Swipe left | Next image (animated transition) |
| Swipe right | Previous image (animated transition) |
| Swipe down | Close preview, return to file list |
| Pinch | Zoom in/out (PhotoView native) |

### Slideshow

**Trigger**: Play button in top-right menu or bottom bar

**Options**: Interval — 3s, 5s (default), 10s, 30s

**Behavior**:
1. Starts from current image
2. Auto-advances through all images in directory
3. Hides all controls during slideshow
4. Single tap pauses/resumes slideshow
5. Tap again to exit slideshow mode

### Media Info Panel

Bottom sheet showing:
- File name
- Dimensions (decoded from image data, e.g., "4032 × 3024")
- File size
- Modified date
- Format (extension)

---

## Text/Code Viewer

### Layout

**Top bar**: Back, filename, search icon (🔍), theme picker (🎨), info icon, more menu

**Content area**:
- Left gutter: line numbers (fixed, don't scroll horizontally)
- Code area: horizontally scrollable (when word wrap off) or wrapped
- Syntax highlighting via `flutter_highlight`

**Bottom status bar**:
- Left: Language name + encoding (e.g., "Python · UTF-8")
- Right: Total lines + file size (e.g., "142 行 · 4.2 KB")

### Features

**Search**:
- Tap 🔍 to expand search bar below top bar
- Real-time highlighting of all matches
- Current match highlighted with background color on the line
- Up/Down navigation buttons
- Match count display (e.g., "3/15")
- Auto-scroll to current match

**Code Themes**:
- Catppuccin Mocha (default dark) — deep purple dark theme
- GitHub Light — clean light theme
- Monokai — classic dark theme
- Auto-select based on system theme (dark → Mocha, light → GitHub Light)
- Manual override via 🎨 icon (bottom sheet selector)

**Word Wrap Toggle**:
- Default: word wrap on for text files, off for code files
- Toggle via more menu (⋮)
- When off: horizontal scroll enabled, line numbers stay fixed

**Supported Languages** (for highlighting):
Python, JavaScript, TypeScript, JSON, HTML, CSS, Markdown, YAML, Go, Rust, Java, C/C++, Shell, SQL, XML, TOML

### File Type → Language Mapping

| Extensions | Language |
|-----------|----------|
| `.py` | Python |
| `.js` | JavaScript |
| `.ts` | TypeScript |
| `.json` | JSON |
| `.html`, `.htm` | HTML |
| `.css` | CSS |
| `.md` | Markdown |
| `.yaml`, `.yml` | YAML |
| `.go` | Go |
| `.rs` | Rust |
| `.java` | Java |
| `.c`, `.cpp`, `.h` | C/C++ |
| `.sh`, `.bash` | Shell |
| `.sql` | SQL |
| `.xml` | XML |
| `.toml` | TOML |
| `.txt`, `.csv`, `.log` | Plain text (no highlighting) |

---

## Adaptive Theme

The app currently uses `ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true)`.

**Dark mode**:
- Player backgrounds: deep purple gradients (`#0f0c29` → `#1a1040`)
- Control bars: semi-transparent black with blur
- Text: white with varying opacity
- Accent: `#6C63FF` (purple) + `#48c6ef` (cyan)

**Light mode**:
- Player backgrounds: light purple gradients (`#f0eeff` → `#ffffff`)
- Control bars: semi-transparent white
- Text: dark grey/black
- Accent: same `#6C63FF` + `#48c6ef`

**Detection**: Use `Theme.of(context).brightness == Brightness.dark` to switch.

---

## Shared Components

### SleepTimerManager

Stateful manager (can be a ChangeNotifier or simple class with callbacks):
- Stores remaining duration
- Ticks every second
- Fires callback on expiry
- Exposes `start(Duration)`, `cancel()`, `isActive`, `remainingFormatted`

### PlaylistManager

Stateful manager:
- Holds list of file items from current directory
- Tracks current index
- Provides `next()`, `previous()`, `hasNext`, `hasPrevious`
- Filters by media type (video files for video player, audio for audio player)
- Auto-advances on playback completion

### GestureHandler

A `StatefulWidget` wrapper using `GestureDetector`:
- Detects single tap, double tap (with zone detection: left/center/right third)
- Detects horizontal/vertical drags with zone detection (left half / right half)
- Reports gesture events to parent via callbacks
- Debounces to prevent tap/sway conflicts

### MediaInfoPanel

Reusable bottom sheet widget:
- Takes file metadata as input
- Displays in consistent format across all file types
- Extra fields per type (resolution for video/image, codec for video, dimensions for image)

---

## Integration Changes

### FileListScreen

Update tap handler: instead of pushing `FilePreviewScreen`, push `MediaPlayerScreen` with:
- `api` (ApiService)
- `filePath` (String)
- `fileName` (String)
- `directoryFiles` (List — all files in the directory, for playlist)

### FilePreviewScreen

Keep as fallback for unsupported file types. Remove video/audio/image/text handling — those are now in `MediaPlayerScreen`.

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Network error loading media | Show error state with retry button |
| Unsupported file type | Show "Preview not available" message |
| Video/audio initialization failure | Show error overlay with file name, retry option |
| Gesture conflicts | Single tap wins over drag start; double-tap detected via 300ms delay |
| Large file loading | Show loading indicator with file name |

---

## Out of Scope

- Lyrics display (no lyrics API available)
- EXIF data extraction (requires `exif` package, adds complexity for minimal value)
- Video thumbnail preview in playlist (requires server-side thumbnail endpoint)
- Background audio playback (requires platform-specific service)
- File delete/rename operations (requires new server API endpoints)
