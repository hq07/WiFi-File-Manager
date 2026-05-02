import os
import tempfile
from fastapi.testclient import TestClient
from server.main import app, config


def setup_function():
    """Reset config before each test."""
    config.password_hash = None
    config.shared_dirs = []


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
