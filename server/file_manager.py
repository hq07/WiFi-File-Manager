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
