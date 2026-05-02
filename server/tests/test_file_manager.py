# server/tests/test_file_manager.py
import os
import tempfile
from server.file_manager import list_files, detect_disks, validate_path


def test_list_files_in_directory():
    with tempfile.TemporaryDirectory() as tmpdir:
        os.makedirs(os.path.join(tmpdir, "subfolder"))
        with open(os.path.join(tmpdir, "test.txt"), "w") as f:
            f.write("hello")

        items = list_files(tmpdir)
        names = [i["name"] for i in items]
        assert "test.txt" in names
        assert "subfolder" in names

        txt_item = next(i for i in items if i["name"] == "test.txt")
        assert txt_item["type"] == "file"
        assert txt_item["size"] == 5

        folder_item = next(i for i in items if i["name"] == "subfolder")
        assert folder_item["type"] == "folder"


def test_validate_path_rejects_traversal():
    assert validate_path("/shared", "/shared/../../../etc/passwd") is False
    assert validate_path("/shared", "/shared/subfolder/file.txt") is True
    assert validate_path("/shared", "/shared") is True


def test_detect_disks_returns_list():
    disks = detect_disks()
    assert isinstance(disks, list)
