import json
import os
import sys
import uuid
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


DEFAULT_UPLOADS_DIR = os.path.join(os.path.expanduser("~"), "WiFi-Manager-Uploads")
_DEFAULT_CONFIG = "config.win.json" if sys.platform == "win32" else "config.json"


class Config:
    def __init__(self, config_path: str = _DEFAULT_CONFIG):
        self.config_path = config_path
        self.port: int = 7777
        self.password_hash: str | None = None
        self.shared_dirs: list[dict] = []
        self.uploads_dir: str = DEFAULT_UPLOADS_DIR
        self.hide_dot_underscore: bool = True
        self.sort_field: str = "name"
        self.sort_ascending: bool = True
        self._load()
        self._ensure_uploads_dir()

    def _load(self):
        if os.path.exists(self.config_path):
            with open(self.config_path, "r") as f:
                data = json.load(f)
            self.port = data.get("port", 7777)
            self.password_hash = data.get("password_hash")
            self.shared_dirs = data.get("shared_dirs", [])
            self.uploads_dir = data.get("uploads_dir", DEFAULT_UPLOADS_DIR)
            self.hide_dot_underscore = data.get("hide_dot_underscore", True)
            self.sort_field = data.get("sort_field", "name")
            self.sort_ascending = data.get("sort_ascending", True)
            # Backfill visible field for old configs
            for d in self.shared_dirs:
                d.setdefault("visible", True)
        else:
            self._save()

    def _save(self):
        with open(self.config_path, "w") as f:
            json.dump({
                "port": self.port,
                "password_hash": self.password_hash,
                "shared_dirs": self.shared_dirs,
                "uploads_dir": self.uploads_dir,
                "hide_dot_underscore": self.hide_dot_underscore,
                "sort_field": self.sort_field,
                "sort_ascending": self.sort_ascending,
            }, f, indent=2)

    def _ensure_uploads_dir(self):
        """Create uploads directory if not exists and ensure it's in shared_dirs."""
        os.makedirs(self.uploads_dir, exist_ok=True)
        abs_uploads = os.path.abspath(self.uploads_dir)
        already_shared = any(
            os.path.abspath(d["path"]) == abs_uploads
            for d in self.shared_dirs
        )
        if not already_shared:
            share_id = str(uuid.uuid4())[:8]
            self.shared_dirs.append({"id": share_id, "path": abs_uploads, "visible": True})
            self._save()

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
        self.shared_dirs.append({"id": share_id, "path": path, "visible": True})
        self._save()
        return share_id

    def remove_shared_dir(self, share_id: str):
        self.shared_dirs = [d for d in self.shared_dirs if d["id"] != share_id]
        self._save()

    def set_visible(self, share_id: str, visible: bool) -> bool:
        for d in self.shared_dirs:
            if d["id"] == share_id:
                d["visible"] = visible
                self._save()
                return True
        return False

    @staticmethod
    def normalize_path(path: str) -> str:
        """Normalize path separators and drive letters for the current OS."""
        path = path.replace("\\", "/")
        # On macOS, convert Windows drive letters (e.g. X:/) to /Volumes/X/
        if sys.platform != "win32" and len(path) >= 2 and path[1] == ":":
            drive = path[0].upper()
            remainder = path[2:]  # strip "X:"
            path = f"/Volumes/{drive}{remainder}"
        # Collapse consecutive slashes (preserve leading // for UNC if needed)
        while "//" in path:
            path = path.replace("//", "/")
        return path

    def is_path_allowed(self, path: str) -> bool:
        """Check if path is within any shared directory or under external drives."""
        path = os.path.abspath(self.normalize_path(path))
        if path == "/":
            return True
        # Always allow external disks
        if sys.platform == "win32":
            if len(path) >= 2 and path[1] == ':':
                return True
        elif path.startswith("/Volumes/"):
            return True
        for d in self.shared_dirs:
            shared = os.path.abspath(self.normalize_path(d["path"]))
            if path == shared or path.startswith(shared + os.sep):
                return True
        return False

    def get_settings(self) -> dict:
        return {
            "hide_dot_underscore": self.hide_dot_underscore,
            "sort_field": self.sort_field,
            "sort_ascending": self.sort_ascending,
        }

    def update_settings(self, settings: dict):
        if "hide_dot_underscore" in settings:
            self.hide_dot_underscore = bool(settings["hide_dot_underscore"])
        if "sort_field" in settings and settings["sort_field"] in ("name", "size", "date"):
            self.sort_field = settings["sort_field"]
        if "sort_ascending" in settings:
            self.sort_ascending = bool(settings["sort_ascending"])
        self._save()

    def get_shared_dir_by_id(self, share_id: str) -> str | None:
        for d in self.shared_dirs:
            if d["id"] == share_id:
                return d["path"]
        return None
