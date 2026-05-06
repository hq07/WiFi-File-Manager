import json
import os
import socket
import subprocess
import asyncio
import platform
import shutil
import sys as _sys
import hashlib
from fastapi import FastAPI, HTTPException, Depends, Query, UploadFile, File, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.responses import StreamingResponse
from starlette.responses import FileResponse, Response, RedirectResponse
from fastapi.staticfiles import StaticFiles
from server.config import Config
from server.auth import create_token, verify_token, TOKEN_EXPIRE_HOURS
from server.models import (
    LoginRequest, LoginResponse, ShareItem, ShareRequest, PatchShareRequest,
    FileItem, FileListResponse, UploadResponse, DiskInfo,
    SyncHistoryRequest, SyncFavoritesRequest,
)
from server.file_manager import list_files, get_file_metadata, validate_path, detect_disks, get_content_type

config = Config()
app = FastAPI(title="WiFi File Manager")
security = HTTPBearer()

CHUNK_SIZE = 64 * 1024  # 64 KB
THUMB_CACHE_DIR = os.path.join(os.path.dirname(__file__), "data", "thumb_cache")


UF_OFFLINE = 0x00001000


def _thumb_path(path: str) -> str:
    """Return cached thumbnail path for a given file."""
    os.makedirs(THUMB_CACHE_DIR, exist_ok=True)
    h = hashlib.md5(path.encode()).hexdigest()[:12]
    return os.path.join(THUMB_CACHE_DIR, f"{h}.jpg")


def _generate_thumbnail(path: str, max_size: int = 320) -> str | None:
    """Generate a thumbnail image and return its path. Returns None on failure.
    Uses ffmpeg for videos, sips on macOS for images, PIL as fallback."""
    cache = _thumb_path(path)
    if os.path.exists(cache):
        return cache
    ext = os.path.splitext(path)[1].lower()
    video_exts = {'.mp4', '.avi', '.mkv', '.mov', '.webm', '.flv', '.wmv'}
    image_exts = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tiff', '.heic'}
    try:
        if ext in video_exts:
            subprocess.run(
                ['ffmpeg', '-y', '-i', path, '-vf', f'scale={max_size}:{max_size}:force_original_aspect_ratio=decrease',
                 '-vframes', '1', '-q:v', '5', '-f', 'mjpeg', cache],
                capture_output=True, timeout=15, check=True)
        elif ext in image_exts:
            if _sys.platform == 'darwin':
                subprocess.run(
                    ['sips', '-Z', str(max_size), '--setProperty', 'format', 'jpeg',
                     path, '--out', cache], capture_output=True, timeout=10, check=True)
            else:
                try:
                    from PIL import Image
                    img = Image.open(path)
                    img.thumbnail((max_size, max_size))
                    img.convert('RGB').save(cache, 'JPEG', quality=75)
                except ImportError:
                    subprocess.run(
                        ['ffmpeg', '-y', '-i', path, '-vf', f'scale={max_size}:{max_size}:force_original_aspect_ratio=decrease',
                         '-vframes', '1', '-q:v', '5', '-f', 'mjpeg', cache],
                        capture_output=True, timeout=15, check=True)
        else:
            return None
        return cache if os.path.exists(cache) else None
    except Exception:
        return None


def _is_evicted(path: str) -> bool:
    """Detect iCloud-evicted files via macOS UF_OFFLINE flag.
    os.stat reports full file size for placeholders — only the flag reveals truth."""
    try:
        result = subprocess.run(
            ["/usr/bin/stat", "-f", "%f", path],
            capture_output=True, text=True, timeout=2,
        )
        if result.returncode == 0:
            return bool(int(result.stdout.strip()) & UF_OFFLINE)
    except Exception:
        pass
    return False


def _read_chunks_os(fd: int, offset: int, length: int | None):
    """Read file in chunks using os.read (low-level, no buffering).
    For iCloud files: os.read blocks until the requested chunk is available."""
    try:
        os.lseek(fd, offset, os.SEEK_SET)
        remaining = length
        while True:
            want = CHUNK_SIZE if remaining is None else min(CHUNK_SIZE, remaining)
            if want <= 0:
                break
            chunk = os.read(fd, want)
            if not chunk:
                break
            yield chunk
            if remaining is not None:
                remaining -= len(chunk)
    finally:
        os.close(fd)


def get_preview_response(path: str, request: Request, content_type: str) -> Response:
    """Build a streaming response with Range support. Handles iCloud evicted files."""
    if _is_evicted(path):
        print(f"[iCloud] File evicted, triggering download: {os.path.basename(path)}")
        subprocess.Popen(
            ["/usr/bin/brctl", "download", path],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        # open() triggers the actual download — blocks until enough data is on disk
        fd = os.open(path, os.O_RDONLY)
        file_size = os.fstat(fd).st_size
        if file_size == 0:
            os.close(fd)
            raise HTTPException(503, "File not yet available from iCloud")
        print(f"[iCloud] File now available — {file_size / 1048576:.1f} MB")
    else:
        fd = os.open(path, os.O_RDONLY)
        file_size = os.fstat(fd).st_size

    try:
        range_header = request.headers.get("range")
        if range_header:
            range_spec = range_header.replace("bytes=", "")
            start_str, end_str = range_spec.split("-", 1)
            rs = int(start_str) if start_str else 0
            re = int(end_str) if end_str else file_size - 1
            if rs >= file_size:
                os.close(fd)
                return Response(status_code=416, headers={"Content-Range": f"bytes */{file_size}"})
            length = re - rs + 1
            return StreamingResponse(
                _read_chunks_os(fd, rs, length),
                status_code=206,
                media_type=content_type,
                headers={
                    "Content-Length": str(length),
                    "Content-Range": f"bytes {rs}-{re}/{file_size}",
                    "Accept-Ranges": "bytes",
                },
            )
        return StreamingResponse(
            _read_chunks_os(fd, 0, None),
            media_type=content_type,
            headers={
                "Content-Length": str(file_size),
                "Accept-Ranges": "bytes",
            },
        )
    except Exception:
        os.close(fd)
        raise


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
        ShareItem(id=d["id"], path=d["path"], name=os.path.basename(d["path"]),
                  visible=d.get("visible", True))
        for d in config.shared_dirs
    ]


@app.post("/api/shares", response_model=ShareItem)
def add_share(req: ShareRequest, user=Depends(get_current_user)):
    if not os.path.isdir(req.path):
        raise HTTPException(status_code=400, detail="Directory does not exist")
    share_id = config.add_shared_dir(req.path)
    # Find the entry to get its visible field
    entry = next(d for d in config.shared_dirs if d["id"] == share_id)
    return ShareItem(id=share_id, path=req.path, name=os.path.basename(req.path),
                     visible=entry.get("visible", True))


@app.delete("/api/shares/{share_id}")
def remove_share(share_id: str, user=Depends(get_current_user)):
    config.remove_shared_dir(share_id)
    return {"status": "ok"}


@app.patch("/api/shares/{share_id}", response_model=ShareItem)
def update_share(share_id: str, req: PatchShareRequest, user=Depends(get_current_user)):
    if not config.set_visible(share_id, req.visible):
        raise HTTPException(status_code=404, detail="Share not found")
    d = next(d for d in config.shared_dirs if d["id"] == share_id)
    return ShareItem(id=d["id"], path=d["path"], name=os.path.basename(d["path"]),
                     visible=d.get("visible", True))


@app.get("/api/files", response_model=FileListResponse)
def browse_files(path: str, user=Depends(get_current_user)):
    if not config.is_path_allowed(path):
        raise HTTPException(status_code=403, detail="Access denied")
    if not os.path.isdir(path):
        raise HTTPException(status_code=404, detail="Directory not found")
    # Virtual root: show disks + shared dirs instead of listing /
    if path == "/" or path == "\\":
        entries = []
        for disk in detect_disks():
            entries.append(FileItem(name=disk["name"], type="folder", size=disk.get("total", 0),
                                    modified="", path=disk["path"]))
        for d in config.shared_dirs:
            p = d["path"]
            if os.path.isdir(p):
                try:
                    st = os.statvfs(p)
                    total = st.f_blocks * st.f_frsize
                except OSError:
                    total = 0
                entries.append(FileItem(name=os.path.basename(p) or p, type="folder",
                                        size=total, modified="", path=p))
        return FileListResponse(path="/", items=sorted(entries, key=lambda e: e.name.lower()))
    return FileListResponse(path=path, items=list_files(path))


@app.get("/api/files/search")
def search_files(q: str, user=Depends(get_current_user)):
    roots = [d["path"] for d in config.shared_dirs]
    results = []
    query = q.lower()
    for root in roots:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            for name in filenames + dirnames:
                if query in name.lower():
                    full = os.path.join(dirpath, name)
                    is_dir = os.path.isdir(full)
                    size = 0
                    try:
                        if not is_dir:
                            size = os.path.getsize(full)
                    except OSError:
                        pass
                    results.append({
                        "name": name,
                        "path": full,
                        "parent": dirpath,
                        "type": "folder" if is_dir else "file",
                        "size": size,
                    })
                    if len(results) >= 100:
                        return {"items": results}
    return {"items": results}


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


@app.post("/api/files/trash")
def trash_file(path: str, user=Depends(get_current_user)):
    """Move file/folder to system trash."""
    from send2trash import send2trash
    if not config.is_path_allowed(path):
        raise HTTPException(status_code=403, detail="Access denied")
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="File not found")
    send2trash(path)
    return {"status": "ok"}


@app.delete("/api/files/delete")
def delete_file(path: str, user=Depends(get_current_user)):
    """Permanent delete — only used from trash management screen."""
    if platform.system() != "Darwin":
        raise HTTPException(status_code=400, detail="Trash management is only supported on macOS")
    trash_dir = os.path.expanduser("~/.Trash")
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="File not found")
    if not os.path.realpath(path).startswith(os.path.realpath(trash_dir)):
        raise HTTPException(status_code=403, detail="Can only permanently delete from trash")
    if os.path.isfile(path):
        os.remove(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)
    return {"status": "ok"}


@app.get("/api/trash")
def list_trash(path: str = "", user=Depends(get_current_user)):
    """List files in system trash."""
    if platform.system() != "Darwin":
        return []
    trash_dir = os.path.expanduser("~/.Trash")
    target = os.path.join(trash_dir, path) if path else trash_dir
    if not os.path.realpath(target).startswith(os.path.realpath(trash_dir)):
        raise HTTPException(status_code=403, detail="Access denied")
    if not os.path.isdir(target):
        raise HTTPException(status_code=404, detail="Directory not found")
    items = []
    for name in sorted(os.listdir(target)):
        if name.startswith('.'):
            continue
        full_path = os.path.join(target, name)
        try:
            stat = os.stat(full_path)
            items.append({
                "name": name,
                "path": full_path,
                "is_dir": os.path.isdir(full_path),
                "size": stat.st_size if os.path.isfile(full_path) else 0,
                "deleted_at": os.path.getmtime(full_path),
            })
        except OSError:
            continue
    return items


@app.post("/api/trash/restore")
def restore_trash(name: str, user=Depends(get_current_user)):
    """Restore a file from system trash."""
    if platform.system() != "Darwin":
        raise HTTPException(status_code=400, detail="Trash restore is only supported on macOS")
    trash_dir = os.path.expanduser("~/.Trash")
    src = os.path.join(trash_dir, name)
    if not os.path.exists(src):
        raise HTTPException(status_code=404, detail="File not found in trash")
    home = os.path.expanduser("~")
    dst = os.path.join(home, name)
    if os.path.exists(dst):
        base, ext = os.path.splitext(name)
        i = 1
        while os.path.exists(dst):
            dst = os.path.join(home, f"{base} ({i}){ext}")
            i += 1
    shutil.move(src, dst)
    return {"status": "ok", "restored_to": dst}


@app.post("/api/trash/empty")
def empty_trash(user=Depends(get_current_user)):
    """Permanently delete all files in system trash."""
    if platform.system() != "Darwin":
        return {"status": "ok", "deleted": 0}
    trash_dir = os.path.expanduser("~/.Trash")
    if not os.path.isdir(trash_dir):
        return {"status": "ok", "deleted": 0}
    count = 0
    for name in os.listdir(trash_dir):
        if name.startswith('.'):
            continue
        full_path = os.path.join(trash_dir, name)
        try:
            if os.path.isfile(full_path):
                os.remove(full_path)
            elif os.path.isdir(full_path):
                shutil.rmtree(full_path)
            count += 1
        except OSError:
            continue
    return {"status": "ok", "deleted": count}


@app.get("/api/files/metadata")
def file_metadata(path: str, filename: str, user=Depends(get_current_user)):
    if not config.is_path_allowed(path):
        raise HTTPException(status_code=403, detail="Access denied")
    meta = get_file_metadata(path, filename)
    return meta or {}


@app.post("/api/files/upload", response_model=UploadResponse)
async def upload_file(path: str, file: UploadFile = File(...), subdir: str = "", user=Depends(get_current_user)):
    if not config.is_path_allowed(path):
        raise HTTPException(status_code=403, detail="Access denied")
    if not os.path.isdir(path):
        raise HTTPException(status_code=404, detail="Target directory not found")
    target = os.path.join(path, subdir) if subdir else path
    if subdir:
        os.makedirs(target, exist_ok=True)
    dest = os.path.join(target, file.filename)
    if os.path.exists(dest):
        raise HTTPException(status_code=409, detail=f"文件已存在: {file.filename}")
    content = await file.read()
    with open(dest, "wb") as f:
        f.write(content)
    return UploadResponse(filename=file.filename, size=len(content))



@app.post("/api/files/rename")
def rename_file(path: str, new_name: str, user=Depends(get_current_user)):
    if not config.is_path_allowed(path):
        raise HTTPException(status_code=403, detail="Access denied")
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="File not found")
    parent = os.path.dirname(path)
    new_path = os.path.join(parent, new_name)
    if os.path.exists(new_path):
        raise HTTPException(status_code=409, detail="A file with that name already exists")
    os.rename(path, new_path)
    return {"status": "ok", "new_path": new_path}


@app.get("/api/files/preview")
def preview_file(path: str, request: Request, thumbnail: bool = False, user=Depends(get_current_user_query)):
    if not config.is_path_allowed(path):
        raise HTTPException(status_code=403, detail="Access denied")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="File not found")
    if thumbnail:
        thumb = _generate_thumbnail(path)
        if thumb:
            return FileResponse(thumb, media_type="image/jpeg",
                                headers={"Cache-Control": "public, max-age=86400"})
        return Response(status_code=202, content="Thumbnail generating")
    filename = os.path.basename(path)
    content_type = get_content_type(filename)
    return get_preview_response(path, request, content_type)


@app.get("/api/disks", response_model=list[DiskInfo])
def get_disks(user=Depends(get_current_user)):
    return [DiskInfo(**d) for d in detect_disks()]


@app.get("/api/uploads-dir")
def get_uploads_dir(user=Depends(get_current_user)):
    return {"path": config.uploads_dir, "name": "上传文件夹"}


@app.get("/api/common-paths")
def get_common_paths(user=Depends(get_current_user)):
    home = os.path.expanduser("~")
    if _sys.platform == "win32":
        candidates = [
            ("用户目录", home),
            ("桌面", os.path.join(home, "Desktop")),
            ("文档", os.path.join(home, "Documents")),
            ("下载", os.path.join(home, "Downloads")),
            ("图片", os.path.join(home, "Pictures")),
            ("视频", os.path.join(home, "Videos")),
            ("C盘", "C:\\"),
        ]
    else:
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


def get_local_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


@app.get("/api/discover")
def discover():
    """No-auth endpoint for LAN discovery."""
    return {"ip": get_local_ip()}


_data_dir_name = "data.win" if _sys.platform == "win32" else "data"
SYNC_DATA_DIR = os.path.join(os.path.dirname(__file__), _data_dir_name)


def _sync_path(name: str) -> str:
    os.makedirs(SYNC_DATA_DIR, exist_ok=True)
    return os.path.join(SYNC_DATA_DIR, name)


@app.get("/api/sync/history")
def get_sync_history(user=Depends(get_current_user)):
    path = _sync_path("history.json")
    if os.path.exists(path):
        try:
            with open(path, "r") as f:
                data = json.load(f)
            if isinstance(data, list):
                return data
        except (json.JSONDecodeError, ValueError):
            pass
    return []


@app.post("/api/sync/history")
async def post_sync_history(request: Request, user=Depends(get_current_user)):
    path = _sync_path("history.json")
    try:
        body = await request.json()
    except Exception:
        body = []
    if isinstance(body, dict) and "items" in body:
        body = body["items"]
    with open(path, "w") as f:
        json.dump(body if isinstance(body, list) else [], f)
    return {"ok": True}


@app.get("/api/sync/favorites")
def get_sync_favorites(user=Depends(get_current_user)):
    path = _sync_path("favorites.json")
    if os.path.exists(path):
        try:
            with open(path, "r") as f:
                data = json.load(f)
            if isinstance(data, list):
                return data
        except (json.JSONDecodeError, ValueError):
            pass
    return []


@app.post("/api/sync/favorites")
async def post_sync_favorites(request: Request, user=Depends(get_current_user)):
    path = _sync_path("favorites.json")
    try:
        body = await request.json()
    except Exception:
        body = []
    if isinstance(body, dict) and "items" in body:
        body = body["items"]
    with open(path, "w") as f:
        json.dump(body if isinstance(body, list) else [], f)
    return {"ok": True}


@app.get("/api/cache/info")
def cache_info(user=Depends(get_current_user)):
    total_size = 0
    count = 0
    if os.path.isdir(THUMB_CACHE_DIR):
        for f in os.listdir(THUMB_CACHE_DIR):
            fp = os.path.join(THUMB_CACHE_DIR, f)
            if os.path.isfile(fp):
                total_size += os.path.getsize(fp)
                count += 1
    return {"count": count, "size": total_size}


@app.post("/api/cache/clear")
def cache_clear(user=Depends(get_current_user)):
    if os.path.isdir(THUMB_CACHE_DIR):
        for f in os.listdir(THUMB_CACHE_DIR):
            fp = os.path.join(THUMB_CACHE_DIR, f)
            if os.path.isfile(fp):
                os.remove(fp)
    return {"ok": True}


# Flutter Web static files (served at /app/)
_web_dir = os.path.join(os.path.dirname(__file__), "..", "web")
if os.path.isdir(_web_dir):
    app.mount("/app", StaticFiles(directory=_web_dir, html=True), name="web")

    @app.get("/")
    def root():
        return RedirectResponse(url="/app/")
else:
    @app.get("/")
    def root():
        return {"message": "WiFi File Manager API is running. Flutter Web UI not built yet."}


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
