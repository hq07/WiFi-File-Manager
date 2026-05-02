# WiFi File Manager - Design Spec

## Overview

A LAN-based file manager that lets an Android phone browse, download, upload, and preview files on a computer (including external hard drives) via WiFi. The system consists of a Python FastAPI server on the computer and a Flutter app on the phone.

## Goals

- Phone can access local files and external hard drive files over WiFi
- Browse directory structure, download files, upload files to any shared directory
- Preview images, videos, audio, and text files
- Password-protected access via JWT authentication
- Easy configuration: add/remove shared directories at runtime

## Non-Goals

- Internet access (LAN only)
- File editing in-place
- Multi-user roles / permissions
- File search / indexing

---

## Architecture

```
┌─────────────────┐     WiFi (HTTP/REST)     ┌──────────────────────┐
│  Android App     │ ◄──────────────────────► │  Computer Server      │
│  (Flutter)       │                          │  (Python FastAPI)     │
│                  │   JWT Token auth          │                      │
│  - Browse files  │                          │  - File system access │
│  - Download      │   JSON + Binary Stream   │  - Directory mgmt     │
│  - Upload        │ ◄──────────────────────► │  - User auth          │
│  - Preview media │                          │  - External disk detect│
└─────────────────┘                          └──────────────────────┘
```

**Flow:**
1. Computer starts FastAPI server, listens on LAN IP
2. Phone app enters computer IP + port, logs in to get JWT Token
3. All subsequent requests carry Token in Authorization header

**Tech Stack:**
- Server: FastAPI + uvicorn + python-jose (JWT) + passlib (bcrypt)
- Client: Flutter + dio (HTTP) + flutter_secure_storage (Token)

---

## Server Design

### Directory Structure

```
WiFi-File-Manager/
├── server/
│   ├── main.py              # FastAPI entry point
│   ├── auth.py              # JWT auth, password hashing
│   ├── config.py            # Shared directories, port config
│   ├── file_manager.py      # File browse, upload, download logic
│   ├── models.py            # Pydantic data models
│   └── requirements.txt
├── android/                 # Flutter project
└── README.md
```

### API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/login` | Login, returns JWT Token |
| GET | `/api/shares` | List all shared directories |
| POST | `/api/shares` | Add a new shared directory |
| DELETE | `/api/shares/{id}` | Remove a shared directory |
| GET | `/api/files?path=...` | Browse files/folders at path |
| GET | `/api/files/download?path=...` | Download file (streaming) |
| POST | `/api/files/upload?path=...` | Upload file to target directory |
| GET | `/api/files/preview?path=...` | Preview media (stream + Content-Type) |
| GET | `/api/disks` | List external hard drives |

**Auth:** JWT Token (default 24h expiry), passed as `Authorization: Bearer <token>`.

### API Details

**POST /api/login**
- Request: `{ "username": "admin", "password": "..." }`
- Response: `{ "token": "eyJ...", "expires_in": 86400 }`

**GET /api/files?path=/photos/2024**
- Response: `{ "path": "/photos/2024", "items": [{ "name": "img.jpg", "type": "file", "size": 123456, "modified": "2024-01-01T00:00:00" }] }`

**POST /api/files/upload?path=/photos**
- Request: multipart/form-data with file
- Response: `{ "filename": "img.jpg", "size": 123456 }`

---

## Flutter Client Design

### Pages

```
App
├── LoginScreen          # IP/port + username/password input
├── HomeScreen           # Shared directory list + external disk shortcuts
├── FileListScreen       # Browse files/folders (back navigation)
├── FilePreviewScreen    # Image/video/audio/text preview
└── UploadScreen         # Pick file → choose target directory → upload
```

### Page Details

**LoginScreen:**
- Input fields: server IP, port (default 8000), username, password
- Cache Token locally after successful login
- Auto-fill saved IP on next launch

**HomeScreen:**
- List all shared directories from GET /api/shares
- Section for external disks from GET /api/disks
- Pull-to-refresh to update list

**FileListScreen:**
- Display files and folders as a list
- Tap folder to enter, tap file to preview
- Long press file → menu: Download / Upload here
- Show breadcrumb path at top

**FilePreviewScreen:**
- Images: full-screen with zoom (photo_view)
- Video/Audio: player with controls (video_player)
- Text: scrollable text view

**UploadScreen:**
- Pick file from phone storage (file_picker)
- Choose target shared directory + subfolder
- Upload with progress bar (dio)

### Dependencies

- `dio`: HTTP client + streaming
- `flutter_secure_storage`: secure Token storage
- `video_player`: video/audio playback
- `photo_view`: image zoom viewer
- `file_picker`: phone file selection

---

## Security

- **Password storage:** bcrypt hash on server, first-run setup prompt
- **JWT Token:** configurable expiry (default 24h), app redirects to login on 401
- **Path traversal prevention:** server validates all paths, rejects `../`, only allows access within registered shared directories
- **LAN only:** server binds `0.0.0.0`, app warns user to use trusted WiFi only

---

## Error Handling

| Scenario | Server Response | App Behavior |
|----------|----------------|--------------|
| Network disconnected | N/A | Toast: check WiFi and server status |
| File not found | 404 | Friendly error message |
| Access outside shared dirs | 403 | Access denied message |
| Upload failure | 500 | Retry option, files >500MB confirmation dialog |
| Token expired | 401 | Auto-redirect to login page |

---

## Server Configuration

- Config file: `config.json` (auto-created on first run)
- Fields: listen port, admin password hash, shared directory list
- First run: console prints access URL and initial password
- Shared directories can be added/removed at runtime via API
