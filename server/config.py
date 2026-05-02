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
