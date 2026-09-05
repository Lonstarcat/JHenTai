import sqlite3
from datetime import UTC, datetime
from pathlib import Path

from app.models.gallery_status import GalleryReference, GalleryStatus, GalleryStatusRecord
from app.services.database_service import DatabaseService
from app.services.gallery_cache_service import GalleryCacheService


def test_status_cache_round_trip(tmp_path: Path) -> None:
    database = DatabaseService(tmp_path / "app.db")
    database.initialize()
    root = tmp_path / "library"
    reference = GalleryReference(
        folder_path=root / "100 - title",
        source="metadata",
        gid=100,
        token="abc123",
        gallery_url="https://e-hentai.org/g/100/abc123/",
        local_title="title",
    )
    record = GalleryStatusRecord(
        reference=reference,
        status=GalleryStatus.UPDATE_AVAILABLE,
        checked_at=datetime.now(UTC),
        current_gid=200,
        current_token="def456",
        latest_url="https://e-hentai.org/g/200/def456/",
    )
    cache = GalleryCacheService(database.database_path)

    cache.save(record)
    loaded = cache.get(reference)

    assert loaded is not None
    assert loaded.status is GalleryStatus.UPDATE_AVAILABLE
    assert loaded.current_gid == 200
    assert loaded.from_cache is True
    assert len(cache.list_for_root(root)) == 1


def test_damaged_status_cache_is_ignored(tmp_path: Path) -> None:
    database = DatabaseService(tmp_path / "app.db")
    database.initialize()
    root = tmp_path / "library"
    reference = GalleryReference(
        folder_path=root / "100 - title",
        source="metadata",
        gid=100,
        token="abc123",
        gallery_url=None,
        local_title="title",
    )
    cache = GalleryCacheService(database.database_path)
    cache.save(
        GalleryStatusRecord(
            reference=reference,
            status=GalleryStatus.LATEST,
            checked_at=datetime.now(UTC),
        )
    )
    with sqlite3.connect(database.database_path) as connection:
        connection.execute(
            "UPDATE gallery_status_cache SET local_metadata_json = ?",
            ("{broken",),
        )

    assert cache.get(reference) is None
    assert cache.list_for_root(root) == []


def test_cache_hides_metadata_record_for_archive_gallery(tmp_path: Path) -> None:
    database = DatabaseService(tmp_path / "app.db")
    database.initialize()
    root = tmp_path / "library"
    wrong_reference = GalleryReference(
        folder_path=root / "Archive - 100 - title",
        source="metadata",
        gid=100,
        token="abc123",
        gallery_url=None,
        local_title="title",
    )
    cache = GalleryCacheService(database.database_path)
    cache.save(
        GalleryStatusRecord(
            reference=wrong_reference,
            status=GalleryStatus.LATEST,
            checked_at=datetime.now(UTC),
        )
    )

    assert cache.get(wrong_reference) is None
    assert cache.list_for_root(root) == []
