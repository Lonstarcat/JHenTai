from datetime import UTC, datetime
from pathlib import Path

from app.models.gallery_folder import GalleryFolder, GalleryStorage, GalleryType, UnicodeStatus
from app.services.database_service import DatabaseService


def test_replace_and_load_cached_scan(tmp_path: Path) -> None:
    database = DatabaseService(tmp_path / "app.db")
    database.initialize()
    root = tmp_path / "library"
    gallery = GalleryFolder(
        gallery_id="123",
        gallery_type=GalleryType.NORMAL,
        folder_name="123 - title",
        path=root / "123 - title",
        unicode_status=UnicodeStatus.NFC,
        file_count=2,
        folder_size=10,
        has_metadata=True,
        has_ametadata=False,
        has_comic_info=True,
        modified_ns=1,
        scanned_at=datetime.now(UTC).isoformat(),
    )

    database.replace_scan(root, [gallery], "first")
    cached = database.load_cached(root)

    assert cached[str(gallery.path)].gallery_id == "123"
    assert cached[str(gallery.path)].from_cache is True


def test_cbz_storage_round_trip(tmp_path: Path) -> None:
    database = DatabaseService(tmp_path / "app.db")
    database.initialize()
    root = tmp_path / "library"
    archive = root / "123 - title.cbz"
    item = GalleryFolder("123", GalleryType.NORMAL, archive.name, archive, UnicodeStatus.NFC, 3, 100, True, False, True, 1, "now", storage_type=GalleryStorage.CBZ)
    database.replace_scan(root, [item], "scan")
    assert database.list_galleries(root)[0].storage_type is GalleryStorage.CBZ


def test_replace_scan_removes_stale_rows(tmp_path: Path) -> None:
    database = DatabaseService(tmp_path / "app.db")
    database.initialize()
    root = tmp_path / "library"
    gallery = GalleryFolder(
        gallery_id="123",
        gallery_type=GalleryType.NORMAL,
        folder_name="123 - title",
        path=root / "123 - title",
        unicode_status=UnicodeStatus.NFC,
        file_count=0,
        folder_size=0,
        has_metadata=False,
        has_ametadata=False,
        has_comic_info=False,
        modified_ns=1,
        scanned_at=datetime.now(UTC).isoformat(),
    )
    database.replace_scan(root, [gallery], "first")
    database.replace_scan(root, [], "second")
    assert database.load_cached(root) == {}


def test_initialize_migrates_phase_one_database(tmp_path: Path) -> None:
    import sqlite3

    database_path = tmp_path / "app.db"
    with sqlite3.connect(database_path) as connection:
        connection.executescript(
            """
            CREATE TABLE gallery_folders (
                path TEXT PRIMARY KEY, scan_root TEXT NOT NULL, gallery_id TEXT,
                gallery_type TEXT NOT NULL, folder_name TEXT NOT NULL,
                unicode_status TEXT NOT NULL, file_count INTEGER NOT NULL,
                folder_size INTEGER NOT NULL, has_metadata INTEGER NOT NULL,
                has_ametadata INTEGER NOT NULL, has_comic_info INTEGER NOT NULL,
                modified_ns INTEGER NOT NULL, scanned_at TEXT NOT NULL,
                scan_token TEXT NOT NULL
            );
            """
        )

    database = DatabaseService(database_path)
    database.initialize()

    with sqlite3.connect(database_path) as connection:
        gallery_columns = {row[1] for row in connection.execute("PRAGMA table_info(gallery_folders)")}
        status_columns = {row[1] for row in connection.execute("PRAGMA table_info(gallery_status_cache)")}
    assert {"gid", "token", "gallery_url", "gallery_source", "storage_type"} <= gallery_columns
    assert "scan_root" in status_columns


def test_operation_log_round_trip(tmp_path: Path) -> None:
    database = DatabaseService(tmp_path / "app.db")
    database.initialize()
    database.log_operation("测试", "成功", tmp_path / "a", tmp_path / "b")
    rows = database.list_operation_logs()
    assert len(rows) == 1
    assert rows[0].operation_type == "测试"
    assert rows[0].result == "成功"
