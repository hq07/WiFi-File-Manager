import os
import tempfile
from unittest.mock import patch
from fastapi.testclient import TestClient
from server.main import app, config


def setup_function():
    """Reset config before each test."""
    config.password_hash = None
    config.shared_dirs = []
    # Prevent tests from overwriting the real config.json
    config._save = lambda: None


def test_login_no_password_set():
    client = TestClient(app)
    resp = client.post("/api/login", json={"username": "admin", "password": ""})
    assert resp.status_code == 200
    assert "token" in resp.json()


def test_login_with_password():
    config.set_password("test123")
    client = TestClient(app)

    resp = client.post("/api/login", json={"username": "admin", "password": "wrong"})
    assert resp.status_code == 401

    resp = client.post("/api/login", json={"username": "admin", "password": "test123"})
    assert resp.status_code == 200
    assert "token" in resp.json()


def test_shares_requires_auth():
    client = TestClient(app)
    resp = client.get("/api/shares")
    assert resp.status_code == 401


def test_shares_crud():
    config.set_password("test123")
    client = TestClient(app)
    login = client.post("/api/login", json={"username": "admin", "password": "test123"})
    token = login.json()["token"]
    headers = {"Authorization": f"Bearer {token}"}

    with tempfile.TemporaryDirectory() as tmpdir:
        resp = client.post("/api/shares", json={"path": tmpdir}, headers=headers)
        assert resp.status_code == 200
        share_id = resp.json()["id"]

        resp = client.get("/api/shares", headers=headers)
        assert resp.status_code == 200
        assert len(resp.json()) == 1

        resp = client.delete(f"/api/shares/{share_id}", headers=headers)
        assert resp.status_code == 200

        resp = client.get("/api/shares", headers=headers)
        assert len(resp.json()) == 0


def _auth_headers():
    config.set_password("test123")
    client = TestClient(app)
    login = client.post("/api/login", json={"username": "admin", "password": "test123"})
    return {"Authorization": f"Bearer {login.json()['token']}"}


def test_file_list():
    headers = _auth_headers()
    client = TestClient(app)
    with tempfile.TemporaryDirectory() as tmpdir:
        config.add_shared_dir(tmpdir)
        os.makedirs(os.path.join(tmpdir, "docs"))
        with open(os.path.join(tmpdir, "readme.txt"), "w") as f:
            f.write("hi")

        resp = client.get("/api/files", params={"path": tmpdir}, headers=headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["path"] == tmpdir
        names = [i["name"] for i in data["items"]]
        assert "readme.txt" in names
        assert "docs" in names


def test_file_list_rejects_traversal():
    headers = _auth_headers()
    client = TestClient(app)
    with tempfile.TemporaryDirectory() as tmpdir:
        config.add_shared_dir(tmpdir)
        resp = client.get("/api/files", params={"path": "/etc"}, headers=headers)
        assert resp.status_code == 403


def test_file_download():
    headers = _auth_headers()
    client = TestClient(app)
    with tempfile.TemporaryDirectory() as tmpdir:
        config.add_shared_dir(tmpdir)
        filepath = os.path.join(tmpdir, "data.txt")
        with open(filepath, "w") as f:
            f.write("file content")

        resp = client.get("/api/files/download", params={"path": filepath}, headers=headers)
        assert resp.status_code == 200
        assert resp.content == b"file content"


def test_file_upload():
    headers = _auth_headers()
    client = TestClient(app)
    with tempfile.TemporaryDirectory() as tmpdir:
        config.add_shared_dir(tmpdir)
        resp = client.post(
            "/api/files/upload",
            params={"path": tmpdir},
            files={"file": ("upload.txt", b"uploaded data", "text/plain")},
            headers=headers,
        )
        assert resp.status_code == 200
        assert resp.json()["filename"] == "upload.txt"
        assert os.path.exists(os.path.join(tmpdir, "upload.txt"))


def test_preview_with_query_token():
    config.set_password("test123")
    client = TestClient(app)
    login = client.post("/api/login", json={"username": "admin", "password": "test123"})
    token = login.json()["token"]
    with tempfile.TemporaryDirectory() as tmpdir:
        config.add_shared_dir(tmpdir)
        filepath = os.path.join(tmpdir, "photo.jpg")
        with open(filepath, "wb") as f:
            f.write(b"\xff\xd8\xff\xe0fake jpg")
        resp = client.get("/api/files/preview", params={"path": filepath, "token": token})
        assert resp.status_code == 200


def test_share_visible_field():
    headers = _auth_headers()
    client = TestClient(app)
    with tempfile.TemporaryDirectory() as tmpdir:
        resp = client.post("/api/shares", json={"path": tmpdir}, headers=headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["visible"] is True

        resp = client.get("/api/shares", headers=headers)
        assert resp.json()[0]["visible"] is True
