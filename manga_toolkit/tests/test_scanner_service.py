from pathlib import Path
import json
import zipfile

from app.models.gallery_folder import GalleryStorage, GalleryType
from app.services.scanner_service import LibraryScannerService


def test_scan_first_level_and_metadata(tmp_path: Path) -> None:
    gallery = tmp_path / "2185199 - 漫画"
    gallery.mkdir()
    (gallery / "0.jpg").write_bytes(b"image")
    (gallery / "metadata").write_text("{}", encoding="utf-8")
    (gallery / "ComicInfo.xml").write_text("<ComicInfo/>", encoding="utf-8")
    nested = gallery / "nested"
    nested.mkdir()
    (nested / "ignored.jpg").write_bytes(b"ignored")
    (tmp_path / "thumb").mkdir()

    results = LibraryScannerService().scan(tmp_path)
    scanned = [result.gallery for result in results if result.gallery is not None]

    assert len(scanned) == 1
    item = scanned[0]
    assert item.gallery_type == GalleryType.NORMAL
    assert item.gallery_id == "2185199"
    assert item.file_count == 3
    assert item.folder_size == len(b"image") + len(b"{}") + len(b"<ComicInfo/>")
    assert item.has_metadata is True
    assert item.has_ametadata is False
    assert item.has_comic_info is True


def test_scan_uncancelled_progress(tmp_path: Path) -> None:
    for index in range(12):
        (tmp_path / f"{1000 + index} - item").mkdir()
    progress: list[tuple[int, int, str]] = []

    LibraryScannerService().scan(tmp_path, on_progress=lambda a, b, c: progress.append((a, b, c)))

    assert progress[-1][0:2] == (12, 12)


def test_scan_includes_root_cbz_and_reads_internal_metadata(tmp_path: Path) -> None:
    cbz = tmp_path / "Archive - 3107629 - 漫画.CBZ"
    metadata = {"gid": 3107629, "token": "abcdef1234", "title": "漫画"}
    with zipfile.ZipFile(cbz, "w") as archive:
        archive.writestr("0.jpg", b"image")
        archive.writestr("ametadata", json.dumps(metadata))
        archive.writestr("ComicInfo.xml", "<ComicInfo/>")

    results = LibraryScannerService().scan(tmp_path)
    assert len(results) == 1
    item = results[0].gallery
    assert item is not None
    assert item.storage_type is GalleryStorage.CBZ
    assert item.gallery_type is GalleryType.ARCHIVE
    assert item.gallery_id == "3107629"
    assert item.file_count == 3
    assert item.folder_size == cbz.stat().st_size
    assert item.has_ametadata is True
    assert item.has_comic_info is True
    assert item.gid == 3107629
    assert item.token == "abcdef1234"


def test_scan_keeps_damaged_cbz_in_results(tmp_path: Path) -> None:
    cbz = tmp_path / "123 - damaged.cbz"
    cbz.write_bytes(b"not a zip")
    item = LibraryScannerService().scan(tmp_path)[0].gallery
    assert item is not None
    assert item.storage_type is GalleryStorage.CBZ
    assert item.gallery_id == "123"
    assert item.file_count == 0
