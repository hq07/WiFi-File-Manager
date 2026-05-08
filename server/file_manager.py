# server/file_manager.py
import os
import platform
import shutil
import subprocess
import json
from datetime import datetime, timezone


IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tiff', '.heic'}
VIDEO_EXTS = {'.mp4', '.avi', '.mkv', '.mov', '.webm', '.flv', '.wmv'}
AUDIO_EXTS = {'.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.wma'}
MEDIA_EXTS = IMAGE_EXTS | VIDEO_EXTS | AUDIO_EXTS


def _get_media_metadata(path: str, ext: str) -> dict:
    """Extract duration and/or resolution for media files. Returns {} on failure."""
    meta = {}
    try:
        if ext in IMAGE_EXTS:
            from PIL import Image
            with Image.open(path) as img:
                meta['resolution'] = f"{img.width}x{img.height}"
        elif ext in VIDEO_EXTS | AUDIO_EXTS:
            result = subprocess.run(
                ['ffprobe', '-v', 'quiet', '-print_format', 'json',
                 '-show_format', '-show_streams', path],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                info = json.loads(result.stdout)
                if 'format' in info and 'duration' in info['format']:
                    meta['duration'] = float(info['format']['duration'])
                for stream in info.get('streams', []):
                    if stream.get('codec_type') == 'video' and 'width' in stream:
                        meta['resolution'] = f"{stream['width']}x{stream['height']}"
                        # Compute correct display aspect ratio using SAR
                        sar_str = stream.get('sample_aspect_ratio', '1:1')
                        try:
                            sar_w, sar_h = [int(x) for x in sar_str.split(':')]
                        except (ValueError, AttributeError):
                            sar_w, sar_h = 1, 1
                        if sar_w > 0 and sar_h > 0:
                            dar = (stream['width'] * sar_w) / (stream['height'] * sar_h)
                            meta['display_aspect_ratio'] = round(dar, 6)
                        break
    except Exception:
        pass
    return meta


def list_files(directory: str, hide_dot_underscore: bool = True) -> list[dict]:
    items = []
    for name in sorted(os.listdir(directory)):
        if hide_dot_underscore and name.startswith('._'):
            continue
        full_path = os.path.join(directory, name)
        try:
            stat = os.stat(full_path)
        except OSError:
            continue
        item = {
            "name": name,
            "type": "folder" if os.path.isdir(full_path) else "file",
            "size": stat.st_size,
            "modified": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(),
        }
        if item["type"] == "file":
            ext = os.path.splitext(name)[1].lower()
            if ext in MEDIA_EXTS and stat.st_size < 500 * 1024 * 1024:
                meta = _get_media_metadata(full_path, ext)
                item.update(meta)
        items.append(item)
    return items


def get_folder_info(directory: str, max_depth: int = 3, max_items: int = 5000) -> dict:
    """统计文件夹内各类型文件数量（递归），返回分类计数。"""
    counts = {"image": 0, "video": 0, "audio": 0, "other": 0, "folder": 0}
    total = 0

    for dirpath, dirnames, filenames in os.walk(directory):
        # 计算当前深度
        depth = dirpath[len(directory):].count(os.sep)
        if depth >= max_depth:
            dirnames.clear()
            continue

        # 跳过隐藏文件夹
        dirnames[:] = [d for d in dirnames if not d.startswith('.')]

        for name in filenames:
            if name.startswith('.'):
                continue
            total += 1
            if total > max_items:
                counts["truncated"] = True
                return counts

            ext = os.path.splitext(name)[1].lower()
            if ext in IMAGE_EXTS:
                counts["image"] += 1
            elif ext in VIDEO_EXTS:
                counts["video"] += 1
            elif ext in AUDIO_EXTS:
                counts["audio"] += 1
            else:
                counts["other"] += 1

        counts["folder"] += len(dirnames)

    return counts


def get_file_metadata(directory: str, filename: str) -> dict | None:
    """Get media metadata for a single file. Returns None if not applicable."""
    full_path = os.path.join(directory, filename)
    if not os.path.isfile(full_path):
        return None
    ext = os.path.splitext(filename)[1].lower()
    if ext not in MEDIA_EXTS:
        return None
    return _get_media_metadata(full_path, ext)


def validate_path(shared_dir: str, requested_path: str) -> bool:
    """Check that requested_path is within shared_dir (no traversal)."""
    shared_dir = os.path.abspath(shared_dir)
    requested_path = os.path.abspath(requested_path)
    return requested_path == shared_dir or requested_path.startswith(shared_dir + os.sep)


def detect_disks() -> list[dict]:
    disks = []
    if platform.system() == "Darwin":
        # System disk (Macintosh HD)
        try:
            stat = os.statvfs("/")
            disks.append({
                "name": "Macintosh HD",
                "path": "/",
                "total": stat.f_blocks * stat.f_frsize,
                "free": stat.f_bavail * stat.f_frsize,
            })
        except OSError:
            pass
        # External volumes
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
        try:
            stat = os.statvfs("/")
            disks.append({
                "name": "System Disk",
                "path": "/",
                "total": stat.f_blocks * stat.f_frsize,
                "free": stat.f_bavail * stat.f_frsize,
            })
        except OSError:
            pass
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
                usage = shutil.disk_usage(drive)
                total, free = usage.total, usage.free
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
