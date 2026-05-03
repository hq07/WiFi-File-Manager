import os
import socket
import subprocess
import asyncio
import fcntl
from fastapi import FastAPI, HTTPException, Depends, Query, UploadFile, File, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.responses import StreamingResponse
from starlette.responses import FileResponse, Response
from server.config import Config
from server.auth import create_token, verify_token, TOKEN_EXPIRE_HOURS
from server.models import (
    LoginRequest, LoginResponse, ShareItem, ShareRequest, PatchShareRequest,
    FileItem, FileListResponse, UploadResponse, DiskInfo,
)
from server.file_manager import list_files, validate_path, detect_disks, get_content_type

config = Config()
app = FastAPI(title="WiFi File Manager")
security = HTTPBearer()

CHUNK_SIZE = 64 * 1024  # 64 KB


UF_OFFLINE = 0x00001000


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


@app.delete("/api/files/delete")
def delete_file(path: str, user=Depends(get_current_user)):
    if not config.is_path_allowed(path):
        raise HTTPException(status_code=403, detail="Access denied")
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="File not found")
    if os.path.isfile(path):
        os.remove(path)
    elif os.path.isdir(path):
        import shutil
        shutil.rmtree(path)
    else:
        raise HTTPException(status_code=400, detail="Unsupported file type")
    return {"status": "ok"}


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
def preview_file(path: str, request: Request, user=Depends(get_current_user_query)):
    if not config.is_path_allowed(path):
        raise HTTPException(status_code=403, detail="Access denied")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="File not found")
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
