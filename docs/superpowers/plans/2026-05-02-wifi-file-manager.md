# WiFi File Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a LAN file manager with a Python FastAPI server and Flutter Android app for browsing, downloading, uploading, and previewing files over WiFi.

**Architecture:** FastAPI server exposes REST APIs with JWT auth. Flutter app connects over LAN, caches token, and provides full file management UI. External hard drives are auto-detected.

**Tech Stack:** Python 3.12+, uv (package manager), FastAPI, uvicorn, python-jose, passlib, bcrypt | Flutter 3.x, dio, flutter_secure_storage, video_player, photo_view, file_picker

---

## File Structure

### Server Files

| File | Responsibility |
|------|---------------|
| `pyproject.toml` | Project config and dependencies (uv) |
| `uv.lock` | Lockfile (auto-generated) |
| `server/config.py` | Read/write `config.json`, manage shared dirs, password hash, port |
| `server/auth.py` | Password hashing (bcrypt), JWT create/verify |
| `server/models.py` | Pydantic request/response models |
| `server/file_manager.py` | Path validation, file listing, disk detection, upload/download helpers |
| `server/main.py` | FastAPI app, all route definitions, startup logic |
| `server/tests/test_auth.py` | Auth unit tests |
| `server/tests/test_file_manager.py` | File manager unit tests |
| `server/tests/test_main.py` | API integration tests |

### Flutter Files

| File | Responsibility |
|------|---------------|
| `android/lib/main.dart` | App entry, theme, routing |
| `android/lib/services/api_service.dart` | Dio HTTP client, all API calls, token management |
| `android/lib/screens/login_screen.dart` | Login form (IP, port, username, password) |
| `android/lib/screens/home_screen.dart` | Shared dirs list, external disks |
| `android/lib/screens/file_list_screen.dart` | File/folder browser |
| `android/lib/screens/file_preview_screen.dart` | Image/video/audio/text preview |
| `android/lib/screens/upload_screen.dart` | File picker + upload to target dir |

---

## Part A: Server

---

### Task 1: Project Setup

**Files:**
- Create: `pyproject.toml` (via uv init)
- Create: `server/__init__.py`
- Create: `server/tests/__init__.py`

- [ ] **Step 1: Initialize project with uv**

```bash
cd /Users/hq/python/code/WiFi-File-Manager
uv init --name wifi-file-manager --python 3.12
```

This creates `pyproject.toml`, `.python-version`, `hello.py`. Delete `hello.py` as it's not needed.

- [ ] **Step 2: Add runtime dependencies**

```bash
uv add fastapi uvicorn "python-jose[cryptography]" "passlib[bcrypt]" python-multipart
```

- [ ] **Step 3: Add dev dependencies**

```bash
uv add --dev pytest httpx
```

- [ ] **Step 4: Create init files**

Create empty `server/__init__.py` and `server/tests/__init__.py`.

- [ ] **Step 5: Verify installation**

```bash
uv run uv run python -c "import fastapi; print('OK')"
```

- [ ] **Step 6: Commit**

```bash
git add pyproject.toml uv.lock .python-version server/__init__.py server/tests/__init__.py
git commit -m "chore: initialize project with uv and dependencies"
```

---

### Task 2: Config Module

**Files:**
- Create: `server/config.py`
- Create: `server/tests/test_config.py`

- [ ] **Step 1: Write failing test for config load/save**

```python
# server/tests/test_config.py
import json
import os
import tempfile
from server.config import Config


def test_default_config_created_on_load():
    with tempfile.TemporaryDirectory() as tmpdir:
        cfg_path = os.path.join(tmpdir, "config.json")
        cfg = Config(cfg_path)
        assert cfg.port == 8000
        assert cfg.password_hash is None
        assert cfg.shared_dirs == []


def test_set_password_and_reload():
    with tempfile.TemporaryDirectory() as tmpdir:
        cfg_path = os.path.join(tmpdir, "config.json")
        cfg = Config(cfg_path)
        cfg.set_password("secret123")
        assert cfg.password_hash is not None
        assert cfg.verify_password("secret123")
        assert not cfg.verify_password("wrong")

        cfg2 = Config(cfg_path)
        assert cfg2.verify_password("secret123")


def test_add_and_remove_shared_dir():
    with tempfile.TemporaryDirectory() as tmpdir:
        cfg_path = os.path.join(tmpdir, "config.json")
        cfg = Config(cfg_path)
        share_id = cfg.add_shared_dir(tmpdir)
        assert len(cfg.shared_dirs) == 1
        assert cfg.shared_dirs[0]["id"] == share_id
        assert cfg.shared_dirs[0]["path"] == tmpdir

        cfg.remove_shared_dir(share_id)
        assert len(cfg.shared_dirs) == 0


def test_reject_duplicate_shared_dir():
    with tempfile.TemporaryDirectory() as tmpdir:
        cfg_path = os.path.join(tmpdir, "config.json")
        cfg = Config(cfg_path)
        cfg.add_shared_dir(tmpdir)
        cfg.add_shared_dir(tmpdir)  # duplicate
        assert len(cfg.shared_dirs) == 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && uv run pytest server/tests/test_config.py -v`
Expected: FAIL (ModuleNotFoundError)

- [ ] **Step 3: Implement config.py**

```python
# server/config.py
import json
import os
import uuid
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


class Config:
    def __init__(self, config_path: str = "config.json"):
        self.config_path = config_path
        self.port: int = 8000
        self.password_hash: str | None = None
        self.shared_dirs: list[dict] = []
        self._load()

    def _load(self):
        if os.path.exists(self.config_path):
            with open(self.config_path, "r") as f:
                data = json.load(f)
            self.port = data.get("port", 8000)
            self.password_hash = data.get("password_hash")
            self.shared_dirs = data.get("shared_dirs", [])
        else:
            self._save()

    def _save(self):
        with open(self.config_path, "w") as f:
            json.dump({
                "port": self.port,
                "password_hash": self.password_hash,
                "shared_dirs": self.shared_dirs,
            }, f, indent=2)

    def set_password(self, password: str):
        self.password_hash = pwd_context.hash(password)
        self._save()

    def verify_password(self, password: str) -> bool:
        if not self.password_hash:
            return False
        return pwd_context.verify(password, self.password_hash)

    def add_shared_dir(self, path: str) -> str:
        path = os.path.abspath(path)
        for d in self.shared_dirs:
            if d["path"] == path:
                return d["id"]
        share_id = str(uuid.uuid4())[:8]
        self.shared_dirs.append({"id": share_id, "path": path})
        self._save()
        return share_id

    def remove_shared_dir(self, share_id: str):
        self.shared_dirs = [d for d in self.shared_dirs if d["id"] != share_id]
        self._save()

    def is_path_allowed(self, path: str) -> bool:
        """Check if path is within any shared directory."""
        path = os.path.abspath(path)
        for d in self.shared_dirs:
            shared = os.path.abspath(d["path"])
            if path == shared or path.startswith(shared + os.sep):
                return True
        return False

    def get_shared_dir_by_id(self, share_id: str) -> str | None:
        for d in self.shared_dirs:
            if d["id"] == share_id:
                return d["path"]
        return None
```

- [ ] **Step 4: Run tests**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && uv run pytest server/tests/test_config.py -v`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add server/config.py server/tests/test_config.py
git commit -m "feat: add config module for shared dirs and password management"
```

---

### Task 3: Auth Module

**Files:**
- Create: `server/auth.py`
- Create: `server/tests/test_auth.py`

- [ ] **Step 1: Write failing tests**

```python
# server/tests/test_auth.py
from server.auth import create_token, verify_token


def test_create_and_verify_token():
    token = create_token("admin")
    payload = verify_token(token)
    assert payload is not None
    assert payload["sub"] == "admin"


def test_invalid_token_returns_none():
    payload = verify_token("invalid.token.here")
    assert payload is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && uv run pytest server/tests/test_auth.py -v`
Expected: FAIL

- [ ] **Step 3: Implement auth.py**

```python
# server/auth.py
from datetime import datetime, timedelta, timezone
from jose import JWTError, jwt

SECRET_KEY = "wifi-file-manager-secret-change-in-production"
ALGORITHM = "HS256"
TOKEN_EXPIRE_HOURS = 24


def create_token(username: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(hours=TOKEN_EXPIRE_HOURS)
    return jwt.encode({"sub": username, "exp": expire}, SECRET_KEY, algorithm=ALGORITHM)


def verify_token(token: str) -> dict | None:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except JWTError:
        return None
```

- [ ] **Step 4: Run tests**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && uv run pytest server/tests/test_auth.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add server/auth.py server/tests/test_auth.py
git commit -m "feat: add JWT auth module"
```

---

### Task 4: Pydantic Models

**Files:**
- Create: `server/models.py`

- [ ] **Step 1: Create models.py**

```python
# server/models.py
from pydantic import BaseModel


class LoginRequest(BaseModel):
    username: str
    password: str


class LoginResponse(BaseModel):
    token: str
    expires_in: int


class ShareItem(BaseModel):
    id: str
    path: str
    name: str


class ShareRequest(BaseModel):
    path: str


class FileItem(BaseModel):
    name: str
    type: str  # "file" or "folder"
    size: int
    modified: str


class FileListResponse(BaseModel):
    path: str
    items: list[FileItem]


class UploadResponse(BaseModel):
    filename: str
    size: int


class DiskInfo(BaseModel):
    name: str
    path: str
    total: int
    free: int
```

- [ ] **Step 2: Verify import works**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && uv run python -c "from server.models import LoginRequest; print('OK')"`
Expected: OK

- [ ] **Step 3: Commit**

```bash
git add server/models.py
git commit -m "feat: add Pydantic request/response models"
```

---

### Task 5: File Manager Module

**Files:**
- Create: `server/file_manager.py`
- Create: `server/tests/test_file_manager.py`

- [ ] **Step 1: Write failing tests**

```python
# server/tests/test_file_manager.py
import os
import tempfile
from server.file_manager import list_files, detect_disks, validate_path


def test_list_files_in_directory():
    with tempfile.TemporaryDirectory() as tmpdir:
        os.makedirs(os.path.join(tmpdir, "subfolder"))
        with open(os.path.join(tmpdir, "test.txt"), "w") as f:
            f.write("hello")

        items = list_files(tmpdir)
        names = [i["name"] for i in items]
        assert "test.txt" in names
        assert "subfolder" in names

        txt_item = next(i for i in items if i["name"] == "test.txt")
        assert txt_item["type"] == "file"
        assert txt_item["size"] == 5

        folder_item = next(i for i in items if i["name"] == "subfolder")
        assert folder_item["type"] == "folder"


def test_validate_path_rejects_traversal():
    assert validate_path("/shared", "/shared/../../../etc/passwd") is False
    assert validate_path("/shared", "/shared/subfolder/file.txt") is True
    assert validate_path("/shared", "/shared") is True


def test_detect_disks_returns_list():
    disks = detect_disks()
    assert isinstance(disks, list)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && uv run pytest server/tests/test_file_manager.py -v`
Expected: FAIL

- [ ] **Step 3: Implement file_manager.py**

```python
# server/file_manager.py
import os
import platform
from datetime import datetime, timezone


def list_files(directory: str) -> list[dict]:
    items = []
    for name in sorted(os.listdir(directory)):
        full_path = os.path.join(directory, name)
        stat = os.stat(full_path)
        items.append({
            "name": name,
            "type": "folder" if os.path.isdir(full_path) else "file",
            "size": stat.st_size,
            "modified": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(),
        })
    return items


def validate_path(shared_dir: str, requested_path: str) -> bool:
    """Check that requested_path is within shared_dir (no traversal)."""
    shared_dir = os.path.abspath(shared_dir)
    requested_path = os.path.abspath(requested_path)
    return requested_path == shared_dir or requested_path.startswith(shared_dir + os.sep)


def detect_disks() -> list[dict]:
    disks = []
    if platform.system() == "Darwin":
        volumes_dir = "/Volumes"
        if os.path.isdir(volumes_dir):
            for name in os.listdir(volumes_dir):
                path = os.path.join(volumes_dir, name)
                if os.path.ismount(path) and path != "/":
                    stat = os.statvfs(path)
                    disks.append({
                        "name": name,
                        "path": path,
                        "total": stat.f_blocks * stat.f_frsize,
                        "free": stat.f_bavail * stat.f_frsize,
                    })
    elif platform.system() == "Linux":
        media_dir = f"/media/{os.getenv('USER', 'root')}"
        if os.path.isdir(media_dir):
            for name in os.listdir(media_dir):
                path = os.path.join(media_dir, name)
                if os.path.ismount(path):
                    stat = os.statvfs(path)
                    disks.append({
                        "name": name,
                        "path": path,
                        "total": stat.f_blocks * stat.f_frsize,
                        "free": stat.f_bavail * stat.f_frsize,
                    })
    elif platform.system() == "Windows":
        import string
        for letter in string.ascii_uppercase:
            drive = f"{letter}:\\"
            if os.path.exists(drive):
                import shutil
                total, free = shutil.disk_usage(drive)
                if letter != "C":
                    disks.append({
                        "name": f"Drive {letter}:",
                        "path": drive,
                        "total": total,
                        "free": free,
                    })
    return disks


def get_content_type(filename: str) -> str:
    ext = os.path.splitext(filename)[1].lower()
    types = {
        ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
        ".gif": "image/gif", ".webp": "image/webp", ".bmp": "image/bmp",
        ".mp4": "video/mp4", ".avi": "video/x-msvideo", ".mkv": "video/x-matroska",
        ".mov": "video/quicktime", ".webm": "video/webm",
        ".mp3": "audio/mpeg", ".wav": "audio/wav", ".flac": "audio/flac",
        ".aac": "audio/aac", ".ogg": "audio/ogg",
        ".txt": "text/plain", ".json": "application/json", ".xml": "application/xml",
        ".html": "text/html", ".css": "text/css", ".js": "application/javascript",
        ".py": "text/x-python", ".md": "text/markdown",
        ".pdf": "application/pdf",
    }
    return types.get(ext, "application/octet-stream")
```

- [ ] **Step 4: Run tests**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && uv run pytest server/tests/test_file_manager.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add server/file_manager.py server/tests/test_file_manager.py
git commit -m "feat: add file manager module with listing, validation, disk detection"
```

---

### Task 6: Main App - Auth & Share Routes

**Files:**
- Create: `server/main.py`
- Create: `server/tests/test_main.py`

- [ ] **Step 1: Write failing tests for login and share routes**

```python
# server/tests/test_main.py
import os
import tempfile
from fastapi.testclient import TestClient
from server.main import app, config


def setup_function():
    """Reset config before each test."""
    config.password_hash = None
    config.shared_dirs = []


def test_login_no_password_set():
    client = TestClient(app)
    resp = client.post("/api/login", json={"username": "admin", "password": ""})
    assert resp.status_code == 200
    assert "token" in resp.json()


def test_login_with_password():
    config.set_password("test123")
    client = TestClient(app)

    resp = client.post("/api/login", json={"username": "admin", "password": "wrong"})
    assert resp.status_code == 401

    resp = client.post("/api/login", json={"username": "admin", "password": "test123"})
    assert resp.status_code == 200
    assert "token" in resp.json()


def test_shares_requires_auth():
    client = TestClient(app)
    resp = client.get("/api/shares")
    assert resp.status_code == 401


def test_shares_crud():
    config.set_password("test123")
    client = TestClient(app)
    login = client.post("/api/login", json={"username": "admin", "password": "test123"})
    token = login.json()["token"]
    headers = {"Authorization": f"Bearer {token}"}

    with tempfile.TemporaryDirectory() as tmpdir:
        resp = client.post("/api/shares", json={"path": tmpdir}, headers=headers)
        assert resp.status_code == 200
        share_id = resp.json()["id"]

        resp = client.get("/api/shares", headers=headers)
        assert resp.status_code == 200
        assert len(resp.json()) == 1

        resp = client.delete(f"/api/shares/{share_id}", headers=headers)
        assert resp.status_code == 200

        resp = client.get("/api/shares", headers=headers)
        assert len(resp.json()) == 0
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && uv run pytest server/tests/test_main.py -v`
Expected: FAIL

- [ ] **Step 3: Implement main.py with auth and share routes**

```python
# server/main.py
import os
import socket
from fastapi import FastAPI, HTTPException, Depends, UploadFile, File, Query
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.responses import StreamingResponse, JSONResponse
from server.config import Config
from server.auth import create_token, verify_token, TOKEN_EXPIRE_HOURS
from server.models import (
    LoginRequest, LoginResponse, ShareItem, ShareRequest,
    FileItem, FileListResponse, UploadResponse, DiskInfo,
)
from server.file_manager import list_files, validate_path, detect_disks, get_content_type

config = Config()
app = FastAPI(title="WiFi File Manager")
security = HTTPBearer()


def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    payload = verify_token(credentials.credentials)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return payload


def get_current_user_query(token: str = Query(None), credentials: HTTPAuthorizationCredentials = Depends(HTTPBearer(auto_error=False))):
    """Accept token from Authorization header OR query param (for media URLs)."""
    raw = None
    if credentials:
        raw = credentials.credentials
    elif token:
        raw = token
    if not raw:
        raise HTTPException(status_code=401, detail="Not authenticated")
    payload = verify_token(raw)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return payload


@app.post("/api/login", response_model=LoginResponse)
def login(req: LoginRequest):
    if req.username != "admin":
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if config.password_hash and not config.verify_password(req.password):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    if not config.password_hash:
        config.set_password(req.password)
    token = create_token(req.username)
    return LoginResponse(token=token, expires_in=TOKEN_EXPIRE_HOURS * 3600)


@app.get("/api/shares", response_model=list[ShareItem])
def get_shares(user=Depends(get_current_user)):
    return [
        ShareItem(id=d["id"], path=d["path"], name=os.path.basename(d["path"]))
        for d in config.shared_dirs
    ]


@app.post("/api/shares", response_model=ShareItem)
def add_share(req: ShareRequest, user=Depends(get_current_user)):
    if not os.path.isdir(req.path):
        raise HTTPException(status_code=400, detail="Directory does not exist")
    share_id = config.add_shared_dir(req.path)
    return ShareItem(id=share_id, path=req.path, name=os.path.basename(req.path))


@app.delete("/api/shares/{share_id}")
def remove_share(share_id: str, user=Depends(get_current_user)):
    config.remove_shared_dir(share_id)
    return {"status": "ok"}
```

- [ ] **Step 4: Run tests**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && uv run pytest server/tests/test_main.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add server/main.py server/tests/test_main.py
git commit -m "feat: add FastAPI app with login and share CRUD routes"
```

---

### Task 7: File Routes (browse, download, upload, preview)

**Files:**
- Modify: `server/main.py`
- Modify: `server/tests/test_main.py`

- [ ] **Step 1: Write failing tests for file routes**

Append to `server/tests/test_main.py`:

```python
def _auth_headers():
    config.set_password("test123")
    client = TestClient(app)
    login = client.post("/api/login", json={"username": "admin", "password": "test123"})
    return {"Authorization": f"Bearer {login.json()['token']}"}


def test_file_list():
    headers = _auth_headers()
    client = TestClient(app)
    with tempfile.TemporaryDirectory() as tmpdir:
        config.add_shared_dir(tmpdir)
        os.makedirs(os.path.join(tmpdir, "docs"))
        with open(os.path.join(tmpdir, "readme.txt"), "w") as f:
            f.write("hi")

        resp = client.get("/api/files", params={"path": tmpdir}, headers=headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["path"] == tmpdir
        names = [i["name"] for i in data["items"]]
        assert "readme.txt" in names
        assert "docs" in names


def test_file_list_rejects_traversal():
    headers = _auth_headers()
    client = TestClient(app)
    with tempfile.TemporaryDirectory() as tmpdir:
        config.add_shared_dir(tmpdir)
        resp = client.get("/api/files", params={"path": "/etc"}, headers=headers)
        assert resp.status_code == 403


def test_file_download():
    headers = _auth_headers()
    client = TestClient(app)
    with tempfile.TemporaryDirectory() as tmpdir:
        config.add_shared_dir(tmpdir)
        filepath = os.path.join(tmpdir, "data.txt")
        with open(filepath, "w") as f:
            f.write("file content")

        resp = client.get("/api/files/download", params={"path": filepath}, headers=headers)
        assert resp.status_code == 200
        assert resp.content == b"file content"


def test_file_upload():
    headers = _auth_headers()
    client = TestClient(app)
    with tempfile.TemporaryDirectory() as tmpdir:
        config.add_shared_dir(tmpdir)
        resp = client.post(
            "/api/files/upload",
            params={"path": tmpdir},
            files={"file": ("upload.txt", b"uploaded data", "text/plain")},
            headers=headers,
        )
        assert resp.status_code == 200
        assert resp.json()["filename"] == "upload.txt"
        assert os.path.exists(os.path.join(tmpdir, "upload.txt"))


def test_preview_with_query_token():
    config.set_password("test123")
    client = TestClient(app)
    login = client.post("/api/login", json={"username": "admin", "password": "test123"})
    token = login.json()["token"]
    with tempfile.TemporaryDirectory() as tmpdir:
        config.add_shared_dir(tmpdir)
        filepath = os.path.join(tmpdir, "photo.jpg")
        with open(filepath, "wb") as f:
            f.write(b"\xff\xd8\xff\xe0fake jpg")
        resp = client.get("/api/files/preview", params={"path": filepath, "token": token})
        assert resp.status_code == 200
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && uv run pytest server/tests/test_main.py -v -k "file"`
Expected: FAIL (routes not defined)

- [ ] **Step 3: Add file routes to main.py**

Append to `server/main.py` (after existing routes):

```python
@app.get("/api/files", response_model=FileListResponse)
def browse_files(path: str, user=Depends(get_current_user)):
    if not config.is_path_allowed(path):
        raise HTTPException(status_code=403, detail="Access denied")
    if not os.path.isdir(path):
        raise HTTPException(status_code=404, detail="Directory not found")
    return FileListResponse(path=path, items=list_files(path))


@app.get("/api/files/download")
def download_file(path: str, user=Depends(get_current_user)):
    if not config.is_path_allowed(path):
        raise HTTPException(status_code=403, detail="Access denied")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="File not found")
    filename = os.path.basename(path)
    content_type = get_content_type(filename)
    return StreamingResponse(
        open(path, "rb"),
        media_type=content_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@app.post("/api/files/upload", response_model=UploadResponse)
async def upload_file(path: str, file: UploadFile = File(...), user=Depends(get_current_user)):
    if not config.is_path_allowed(path):
        raise HTTPException(status_code=403, detail="Access denied")
    if not os.path.isdir(path):
        raise HTTPException(status_code=404, detail="Target directory not found")
    dest = os.path.join(path, file.filename)
    content = await file.read()
    with open(dest, "wb") as f:
        f.write(content)
    return UploadResponse(filename=file.filename, size=len(content))


@app.get("/api/files/preview")
def preview_file(path: str, user=Depends(get_current_user_query)):
    if not config.is_path_allowed(path):
        raise HTTPException(status_code=403, detail="Access denied")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="File not found")
    filename = os.path.basename(path)
    content_type = get_content_type(filename)
    return StreamingResponse(open(path, "rb"), media_type=content_type)


@app.get("/api/disks", response_model=list[DiskInfo])
def get_disks(user=Depends(get_current_user)):
    return [DiskInfo(**d) for d in detect_disks()]
```

- [ ] **Step 4: Run all tests**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && uv run pytest server/tests/ -v`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add server/main.py server/tests/test_main.py
git commit -m "feat: add file browse, download, upload, preview, and disk routes"
```

---

### Task 8: Startup & LAN IP Display

**Files:**
- Modify: `server/main.py`

- [ ] **Step 1: Add startup logic to main.py**

Append to `server/main.py`:

```python
def get_local_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


if __name__ == "__main__":
    import uvicorn
    local_ip = get_local_ip()
    port = config.port
    print(f"\n{'='*50}")
    print(f"  WiFi File Manager Server")
    print(f"  Access from phone: http://{local_ip}:{port}")
    if not config.password_hash:
        print(f"  First login will set your password")
    print(f"{'='*50}\n")
    uvicorn.run(app, host="0.0.0.0", port=port)
```

- [ ] **Step 2: Test server starts**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && timeout 3 uv run python -m server.main || true`
Expected: prints the access URL banner

- [ ] **Step 3: Commit**

```bash
git add server/main.py
git commit -m "feat: add startup with LAN IP display"
```

---

## Part B: Flutter Android App

---

### Task 9: Flutter Project Setup

**Files:**
- Create: Flutter project in `android/`

- [ ] **Step 1: Create Flutter project**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && flutter create --org com.wififilemanager --project-name wifi_file_manager android`

- [ ] **Step 2: Add dependencies**

Add to `android/pubspec.yaml` under `dependencies`:

```yaml
  dio: ^5.4.0
  flutter_secure_storage: ^9.0.0
  video_player: ^2.8.0
  photo_view: ^0.15.0
  file_picker: ^6.1.0
  path_provider: ^2.1.0
```

Run: `cd /Users/hq/python/code/WiFi-File-Manager/android && flutter pub get`

- [ ] **Step 3: Commit**

```bash
git add android/
git commit -m "chore: initialize Flutter project with dependencies"
```

---

### Task 10: API Service

**Files:**
- Create: `android/lib/services/api_service.dart`

- [ ] **Step 1: Create API service**

```dart
// android/lib/services/api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? _baseUrl;
  String? _token;

  Future<void> setServer(String ip, String port) async {
    _baseUrl = 'http://$ip:$port';
    await _storage.write(key: 'server_ip', value: ip);
    await _storage.write(key: 'server_port', value: port);
  }

  Future<String?> getSavedIp() => _storage.read(key: 'server_ip');
  Future<String?> getSavedPort() => _storage.read(key: 'server_port');

  Future<bool> login(String username, String password) async {
    try {
      final resp = await _dio.post('$_baseUrl/api/login',
          data: {'username': username, 'password': password});
      _token = resp.data['token'];
      await _storage.write(key: 'token', value: _token);
      return true;
    } on DioException {
      return false;
    }
  }

  Future<void> loadToken() async {
    _token = await _storage.read(key: 'token');
  }

  void clearToken() {
    _token = null;
    _storage.delete(key: 'token');
  }

  bool get isLoggedIn => _token != null;

  Options get _authOptions =>
      Options(headers: {'Authorization': 'Bearer $_token'});

  Future<List<dynamic>> getShares() async {
    final resp =
        await _dio.get('$_baseUrl/api/shares', options: _authOptions);
    return resp.data;
  }

  Future<Map<String, dynamic>> addShare(String path) async {
    final resp = await _dio.post('$_baseUrl/api/shares',
        data: {'path': path}, options: _authOptions);
    return resp.data;
  }

  Future<void> removeShare(String id) async {
    await _dio.delete('$_baseUrl/api/shares/$id', options: _authOptions);
  }

  Future<Map<String, dynamic>> listFiles(String path) async {
    final resp = await _dio.get('$_baseUrl/api/files',
        queryParameters: {'path': path}, options: _authOptions);
    return resp.data;
  }

  Future<void> downloadFile(String path, String savePath,
      void Function(int, int)? onProgress) async {
    await _dio.download('$_baseUrl/api/files/download', savePath,
        queryParameters: {'path': path},
        options: _authOptions,
        onReceiveProgress: onProgress);
  }

  Future<Map<String, dynamic>> uploadFile(
      String targetPath, String filePath,
      void Function(int, int)? onProgress) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final resp = await _dio.post('$_baseUrl/api/files/upload',
        data: formData,
        queryParameters: {'path': targetPath},
        options: _authOptions,
        onSendProgress: onProgress);
    return resp.data;
  }

  String getPreviewUrl(String path) {
    return '$_baseUrl/api/files/preview?path=${Uri.encodeComponent(path)}&token=$_token';
  }

  Future<List<dynamic>> getDisks() async {
    final resp =
        await _dio.get('$_baseUrl/api/disks', options: _authOptions);
    return resp.data;
  }
}
```

- [ ] **Step 2: Verify no syntax errors**

Run: `cd /Users/hq/python/code/WiFi-File-Manager/android && flutter analyze lib/services/api_service.dart`

- [ ] **Step 3: Commit**

```bash
git add android/lib/services/api_service.dart
git commit -m "feat: add API service with all endpoint methods"
```

---

### Task 11: Login Screen

**Files:**
- Create: `android/lib/screens/login_screen.dart`
- Modify: `android/lib/main.dart`

- [ ] **Step 1: Create login screen**

```dart
// android/lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  final ApiService api;
  const LoginScreen({super.key, required this.api});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '8000');
  final _userCtrl = TextEditingController(text: 'admin');
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final ip = await widget.api.getSavedIp();
    final port = await widget.api.getSavedPort();
    if (ip != null) _ipCtrl.text = ip;
    if (port != null) _portCtrl.text = port;
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    await widget.api.setServer(_ipCtrl.text, _portCtrl.text);
    final ok = await widget.api.login(_userCtrl.text, _passCtrl.text);
    if (ok) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen(api: widget.api)),
      );
    } else {
      setState(() { _error = 'Login failed. Check IP, port, and password.'; });
    }
    setState(() { _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WiFi File Manager')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(controller: _ipCtrl, decoration: const InputDecoration(labelText: 'Server IP', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _portCtrl, decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _userCtrl, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading ? const CircularProgressIndicator() : const Text('Login'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create main.dart**

```dart
// android/lib/main.dart
import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ApiService();
    return MaterialApp(
      title: 'WiFi File Manager',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: LoginScreen(api: api),
    );
  }
}
```

- [ ] **Step 3: Verify compilation**

Run: `cd /Users/hq/python/code/WiFi-File-Manager/android && flutter analyze`

- [ ] **Step 4: Commit**

```bash
git add android/lib/main.dart android/lib/screens/login_screen.dart
git commit -m "feat: add main app and login screen"
```

---

### Task 12: Home Screen

**Files:**
- Create: `android/lib/screens/home_screen.dart`

- [ ] **Step 1: Create home screen**

```dart
// android/lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'file_list_screen.dart';

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

// Need this import for the logout nav
import 'login_screen.dart';
```

- [ ] **Step 2: Verify compilation**

Run: `cd /Users/hq/python/code/WiFi-File-Manager/android && flutter analyze`

- [ ] **Step 3: Commit**

```bash
git add android/lib/screens/home_screen.dart
git commit -m "feat: add home screen with shared dirs and external disks"
```

---

### Task 13: File List Screen

**Files:**
- Create: `android/lib/screens/file_list_screen.dart`

- [ ] **Step 1: Create file list screen**

```dart
// android/lib/screens/file_list_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import 'file_preview_screen.dart';

class FileListScreen extends StatefulWidget {
  final ApiService api;
  final String path;
  final String title;
  const FileListScreen({super.key, required this.api, required this.path, required this.title});

  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  late String _currentPath;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.path;
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() { _loading = true; });
    try {
      final data = await widget.api.listFiles(_currentPath);
      setState(() { _items = data['items']; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _onItemTap(Map<String, dynamic> item) {
    if (item['type'] == 'folder') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FileListScreen(
            api: widget.api,
            path: '$_currentPath/${item['name']}',
            title: item['name'],
          ),
        ),
      );
    } else {
      final filePath = '$_currentPath/${item['name']}';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FilePreviewScreen(api: widget.api, path: filePath, name: item['name']),
        ),
      );
    }
  }

  void _onItemLongPress(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Download'),
              onTap: () { Navigator.pop(context); _downloadFile(item); },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload here'),
              onTap: () { Navigator.pop(context); _uploadHere(); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadFile(Map<String, dynamic> item) async {
    final filePath = '$_currentPath/${item['name']}';
    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/${item['name']}';
    try {
      await widget.api.downloadFile(filePath, savePath, (received, total) {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloaded to $savePath')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  Future<void> _uploadHere() async {
    // Placeholder - will be implemented via upload screen
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload: use home screen')));
  }

  IconData _getIcon(String type, String name) {
    if (type == 'folder') return Icons.folder;
    final ext = name.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) return Icons.image;
    if (['mp4', 'avi', 'mkv', 'mov', 'webm'].contains(ext)) return Icons.video_file;
    if (['mp3', 'wav', 'flac', 'aac', 'ogg'].contains(ext)) return Icons.audio_file;
    if (['txt', 'json', 'xml', 'html', 'css', 'js', 'py', 'md'].contains(ext)) return Icons.description;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadFiles,
              child: _items.isEmpty
                  ? const Center(child: Text('Empty directory'))
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        return ListTile(
                          leading: Icon(_getIcon(item['type'], item['name'])),
                          title: Text(item['name']),
                          subtitle: item['type'] == 'file'
                              ? Text(_formatSize(item['size']))
                              : null,
                          onTap: () => _onItemTap(item),
                          onLongPress: () => _onItemLongPress(item),
                        );
                      },
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
```

- [ ] **Step 2: Verify compilation**

Run: `cd /Users/hq/python/code/WiFi-File-Manager/android && flutter analyze`

- [ ] **Step 3: Commit**

```bash
git add android/lib/screens/file_list_screen.dart
git commit -m "feat: add file list screen with browse and long-press actions"
```

---

### Task 14: File Preview Screen

**Files:**
- Create: `android/lib/screens/file_preview_screen.dart`

- [ ] **Step 1: Create file preview screen**

```dart
// android/lib/screens/file_preview_screen.dart
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';

class FilePreviewScreen extends StatefulWidget {
  final ApiService api;
  final String path;
  final String name;
  const FilePreviewScreen({super.key, required this.api, required this.path, required this.name});

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  VideoPlayerController? _videoCtrl;
  String? _textContent;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  String get _ext => widget.name.split('.').last.toLowerCase();

  bool get _isImage => ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(_ext);
  bool get _isVideo => ['mp4', 'avi', 'mkv', 'mov', 'webm'].contains(_ext);
  bool get _isAudio => ['mp3', 'wav', 'flac', 'aac', 'ogg'].contains(_ext);
  bool get _isText => ['txt', 'json', 'xml', 'html', 'css', 'js', 'py', 'md', 'yaml', 'yml', 'toml', 'csv'].contains(_ext);

  Future<void> _loadPreview() async {
    final url = widget.api.getPreviewUrl(widget.path);
    try {
      if (_isText) {
        final resp = await Dio().get(url);
        setState(() { _textContent = resp.data.toString(); _loading = false; });
      } else if (_isVideo || _isAudio) {
        _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(url));
        await _videoCtrl!.initialize();
        setState(() { _loading = false; });
      } else {
        setState(() { _loading = false; });
      }
    } catch (e) {
      setState(() { _textContent = 'Failed to load: $e'; _loading = false; });
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.api.getPreviewUrl(widget.path);
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _isImage
              ? PhotoView(imageProvider: NetworkImage(url))
              : (_isVideo || _isAudio)
                  ? _buildPlayer()
                  : _isText
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(_textContent ?? ''),
                        )
                      : const Center(child: Text('Preview not available')),
    );
  }

  Widget _buildPlayer() {
    if (_videoCtrl == null || !_videoCtrl!.value.isInitialized) {
      return const Center(child: Text('Failed to load media'));
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: _videoCtrl!.value.aspectRatio,
          child: VideoPlayer(_videoCtrl!),
        ),
        VideoProgressIndicator(_videoCtrl!, allowScrubbing: true),
        IconButton(
          icon: Icon(_videoCtrl!.value.isPlaying ? Icons.pause : Icons.play_arrow),
          iconSize: 48,
          onPressed: () {
            setState(() {
              _videoCtrl!.value.isPlaying ? _videoCtrl!.pause() : _videoCtrl!.play();
            });
          },
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify compilation**

Run: `cd /Users/hq/python/code/WiFi-File-Manager/android && flutter analyze`

- [ ] **Step 3: Commit**

```bash
git add android/lib/screens/file_preview_screen.dart
git commit -m "feat: add file preview screen for images, video, audio, and text"
```

---

### Task 15: Upload Screen

**Files:**
- Create: `android/lib/screens/upload_screen.dart`
- Modify: `android/lib/screens/home_screen.dart` (add upload button)

- [ ] **Step 1: Create upload screen**

```dart
// android/lib/screens/upload_screen.dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class UploadScreen extends StatefulWidget {
  final ApiService api;
  const UploadScreen({super.key, required this.api});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  List<dynamic> _shares = [];
  String? _selectedSharePath;
  String? _selectedFilePath;
  String? _selectedFileName;
  double _progress = 0;
  bool _uploading = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    _loadShares();
  }

  Future<void> _loadShares() async {
    final shares = await widget.api.getShares();
    setState(() { _shares = shares; });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFilePath = result.files.single.path;
        _selectedFileName = result.files.single.name;
      });
    }
  }

  Future<void> _upload() async {
    if (_selectedFilePath == null || _selectedSharePath == null) return;
    setState(() { _uploading = true; _progress = 0; _result = null; });
    try {
      await widget.api.uploadFile(
        _selectedSharePath!,
        _selectedFilePath!,
        (sent, total) {
          if (total > 0) setState(() { _progress = sent / total; });
        },
      );
      setState(() { _result = 'Upload successful!'; });
    } catch (e) {
      setState(() { _result = 'Upload failed: $e'; });
    }
    setState(() { _uploading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload File')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _uploading ? null : _pickFile,
              icon: const Icon(Icons.file_open),
              label: Text(_selectedFileName ?? 'Pick a file'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Target directory', border: OutlineInputBorder()),
              value: _selectedSharePath,
              items: _shares.map<DropdownMenuItem<String>>((s) {
                return DropdownMenuItem(value: s['path'] as String, child: Text(s['name'] ?? s['path']));
              }).toList(),
              onChanged: _uploading ? null : (v) { setState(() { _selectedSharePath = v; }); },
            ),
            const SizedBox(height: 24),
            if (_uploading) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('${(_progress * 100).toStringAsFixed(0)}%'),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              Text(_result!, style: TextStyle(color: _result!.contains('successful') ? Colors.green : Colors.red)),
            ],
            const Spacer(),
            ElevatedButton(
              onPressed: (_selectedFilePath != null && _selectedSharePath != null && !_uploading) ? _upload : null,
              child: const Text('Upload'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Add upload button to HomeScreen**

In `android/lib/screens/home_screen.dart`, add import at top:

```dart
import 'upload_screen.dart';
```

Add a FloatingActionButton to the Scaffold:

```dart
floatingActionButton: FloatingActionButton(
  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UploadScreen(api: widget.api))),
  child: const Icon(Icons.upload_file),
),
```

- [ ] **Step 3: Verify compilation**

Run: `cd /Users/hq/python/code/WiFi-File-Manager/android && flutter analyze`

- [ ] **Step 4: Commit**

```bash
git add android/lib/screens/upload_screen.dart android/lib/screens/home_screen.dart
git commit -m "feat: add upload screen with file picker and progress"
```

---

### Task 16: Final Integration Test

**Files:** None (manual testing)

- [ ] **Step 1: Start server locally**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && uv run python -m server.main`

- [ ] **Step 2: Run all server tests**

Run: `cd /Users/hq/python/code/WiFi-File-Manager && uv run pytest server/tests/ -v`
Expected: all PASS

- [ ] **Step 3: Build Flutter APK**

Run: `cd /Users/hq/python/code/WiFi-File-Manager/android && flutter build apk --debug`

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "chore: final integration verified"
```
