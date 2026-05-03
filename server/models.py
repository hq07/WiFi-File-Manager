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
    visible: bool = True


class ShareRequest(BaseModel):
    path: str


class PatchShareRequest(BaseModel):
    visible: bool


class FileItem(BaseModel):
    name: str
    type: str  # "file" or "folder"
    size: int
    modified: str
    duration: float | None = None    # seconds, for audio/video files
    resolution: str | None = None    # "1920x1080", for image/video files


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
