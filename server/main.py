import os
import socket
from fastapi import FastAPI, HTTPException, Depends, Query, UploadFile, File
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.responses import StreamingResponse
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
