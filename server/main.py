import os
import socket
from fastapi import FastAPI, HTTPException, Depends, Query
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from server.config import Config
from server.auth import create_token, verify_token, TOKEN_EXPIRE_HOURS
from server.models import (
    LoginRequest, LoginResponse, ShareItem, ShareRequest,
)

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
