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
