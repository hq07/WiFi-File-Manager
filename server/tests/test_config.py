import json
import os
import tempfile
from server.config import Config


def test_default_config_created_on_load():
    with tempfile.TemporaryDirectory() as tmpdir:
        cfg_path = os.path.join(tmpdir, "config.json")
        cfg = Config(cfg_path)
        assert cfg.port == 8000
        assert cfg.password_hash is None
        assert cfg.shared_dirs == []


def test_set_password_and_reload():
    with tempfile.TemporaryDirectory() as tmpdir:
        cfg_path = os.path.join(tmpdir, "config.json")
        cfg = Config(cfg_path)
        cfg.set_password("secret123")
        assert cfg.password_hash is not None
        assert cfg.verify_password("secret123")
        assert not cfg.verify_password("wrong")

        cfg2 = Config(cfg_path)
        assert cfg2.verify_password("secret123")


def test_add_and_remove_shared_dir():
    with tempfile.TemporaryDirectory() as tmpdir:
        cfg_path = os.path.join(tmpdir, "config.json")
        cfg = Config(cfg_path)
        share_id = cfg.add_shared_dir(tmpdir)
        assert len(cfg.shared_dirs) == 1
        assert cfg.shared_dirs[0]["id"] == share_id
        assert cfg.shared_dirs[0]["path"] == tmpdir

        cfg.remove_shared_dir(share_id)
        assert len(cfg.shared_dirs) == 0


def test_reject_duplicate_shared_dir():
    with tempfile.TemporaryDirectory() as tmpdir:
        cfg_path = os.path.join(tmpdir, "config.json")
        cfg = Config(cfg_path)
        cfg.add_shared_dir(tmpdir)
        cfg.add_shared_dir(tmpdir)  # duplicate
        assert len(cfg.shared_dirs) == 1
