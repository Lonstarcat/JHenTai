from __future__ import annotations

import json
import codecs
import os
import unicodedata
from pathlib import Path

import pytest

from app.models.gallery_folder import GalleryFolder, GalleryStorage, GalleryType, UnicodeStatus
from app.models.toolkit_features import PlanStatus, UnicodeOperationType
from app.services.unicode_operation_service import UnicodeOperationService


def gallery(path: Path, kind: GalleryType = GalleryType.ARCHIVE) -> GalleryFolder:
    return GalleryFolder(
        "123",
        kind,
        path.name,
        path,
        UnicodeStatus.NFD if path.name != unicodedata.normalize("NFC", path.name) else UnicodeStatus.NFC,
        3,
        0,
        True,
        True,
        True,
        1,
        "now",
        storage_type=GalleryStorage.FOLDER,
    )


def test_output_normalization_copies_without_changing_source(tmp_path: Path) -> None:
    nfc = "シャモナベ"
    source = tmp_path / unicodedata.normalize("NFD", f"Archive - 123 - {nfc}")
    source.mkdir()
    original = unicodedata.normalize("NFD", json.dumps({"title": nfc}, ensure_ascii=False))
    (source / "ametadata").write_text(original, encoding="utf-8")
    (source / "0.jpg").write_bytes(b"image")

    service = UnicodeOperationService()
    plans = service.build_normalization_plans([gallery(source)], tmp_path / "out")
    assert len(plans) == 1
    assert plans[0].operation is UnicodeOperationType.COPY_NORMALIZED
    service.execute(plans[0], tmp_path / "backup")

    assert source.exists()
    assert (source / "ametadata").read_text(encoding="utf-8") == original
    assert plans[0].target.name == unicodedata.normalize("NFC", source.name)
    assert (plans[0].target / "ametadata").read_text(encoding="utf-8") == unicodedata.normalize("NFC", original)
    assert (plans[0].target / "0.jpg").read_bytes() == b"image"


def test_in_place_normalization_backs_up_text_and_renames(tmp_path: Path) -> None:
    nfc = "ブルーアーカイブ"
    source = tmp_path / unicodedata.normalize("NFD", f"Archive - 123 - {nfc}")
    source.mkdir()
    original = unicodedata.normalize("NFD", nfc)
    (source / "ComicInfo.xml").write_text(f"<Title>{original}</Title>", encoding="utf-8")
    service = UnicodeOperationService()
    plan = service.build_normalization_plans([gallery(source)], tmp_path, in_place=True)[0]
    backups = service.execute(plan, tmp_path / "backup")
    assert plan.target.is_dir()
    assert unicodedata.is_normalized("NFC", (plan.target / "ComicInfo.xml").read_text(encoding="utf-8"))
    assert len(backups) == 1 and backups[0].is_file()


def test_text_normalization_preserves_utf8_bom_crlf_and_mtime(tmp_path: Path) -> None:
    source = tmp_path / "123 - Title"; source.mkdir()
    path = source / "metadata"
    decomposed = unicodedata.normalize("NFD", "é")
    path.write_bytes(codecs.BOM_UTF8 + f'{{\r\n  "title": "{decomposed}"\r\n}}'.encode("utf-8"))
    os.utime(path, ns=(1_000_000_000, 2_000_000_000))
    item = gallery(source, GalleryType.NORMAL)
    service = UnicodeOperationService()
    plan = service.build_normalization_plans([item], tmp_path / "out")[0]
    service.execute(plan, tmp_path / "backup")
    result = (plan.target / "metadata").read_bytes()
    assert result.startswith(codecs.BOM_UTF8)
    assert b"\r\n" in result
    assert (plan.target / "metadata").stat().st_mtime_ns == path.stat().st_mtime_ns


def test_normalization_plan_refuses_existing_target(tmp_path: Path) -> None:
    nfc = "シャモナベ"
    source = tmp_path / unicodedata.normalize("NFD", f"123 - {nfc}")
    source.mkdir()
    target = tmp_path / "out" / unicodedata.normalize("NFC", source.name)
    target.mkdir(parents=True)
    plan = UnicodeOperationService().build_normalization_plans([gallery(source, GalleryType.NORMAL)], tmp_path / "out")[0]
    assert plan.status is PlanStatus.CONFLICT


def test_copy_refuses_output_inside_source(tmp_path: Path) -> None:
    source = tmp_path / "123 - Title"; source.mkdir()
    (source / "metadata").write_text(unicodedata.normalize("NFD", '{"title":"é"}'), encoding="utf-8")
    item = gallery(source, GalleryType.NORMAL)
    plan = UnicodeOperationService().build_normalization_plans([item], source / "output")[0]
    with pytest.raises(ValueError, match="不能位于"):
        UnicodeOperationService().execute(plan, tmp_path / "backup")


def test_unicode_classification_requires_same_archive_id_and_normalized_name(tmp_path: Path) -> None:
    nfc_name = "Archive - 123 - シャモナベ"
    nfd_name = unicodedata.normalize("NFD", nfc_name)
    first = tmp_path / "first"; second = tmp_path / "second"
    first.mkdir(); second.mkdir()
    nfc_item = GalleryFolder("123", GalleryType.ARCHIVE, nfc_name, first, UnicodeStatus.NFC, 0, 0, False, True, False, 1, "now")
    nfd_item = GalleryFolder("123", GalleryType.ARCHIVE, nfd_name, second, UnicodeStatus.NFD, 0, 0, False, True, False, 1, "now")
    plans = UnicodeOperationService().build_classification_plans([nfc_item, nfd_item], tmp_path / "out")
    assert len(plans) == 2
    wrong_id = GalleryFolder("999", GalleryType.ARCHIVE, nfd_name, second, UnicodeStatus.NFD, 0, 0, False, True, False, 1, "now")
    assert UnicodeOperationService().build_classification_plans([nfc_item, wrong_id], tmp_path / "out") == []


def test_merge_uses_newer_metadata_and_older_image_without_deleting_sources(tmp_path: Path) -> None:
    nfc_path = tmp_path / "nfc-source"
    nfd_path = tmp_path / "nfd-source"
    nfc_path.mkdir(); nfd_path.mkdir()
    (nfc_path / "ametadata").write_text('{"title":"old"}', encoding="utf-8")
    (nfd_path / "ametadata").write_text('{"title":"new"}', encoding="utf-8")
    (nfc_path / "0.jpg").write_bytes(b"old-image")
    (nfd_path / "0.jpg").write_bytes(b"new-image")
    os.utime(nfc_path / "ametadata", (1, 1)); os.utime(nfd_path / "ametadata", (2, 2))
    os.utime(nfc_path / "0.jpg", (1, 1)); os.utime(nfd_path / "0.jpg", (2, 2))

    service = UnicodeOperationService()
    nfc_gallery = gallery(nfc_path)
    nfd_gallery = GalleryFolder(
        "123", GalleryType.ARCHIVE, unicodedata.normalize("NFD", "Archive - 123 - シャモナベ"),
        nfd_path, UnicodeStatus.NFD, 2, 0, True, True, False, 1, "now",
    )
    plan = service.build_merge_plans([nfc_gallery, nfd_gallery], tmp_path / "result")[0]
    service.execute(plan, tmp_path / "backup")
    assert json.loads((plan.target / "ametadata").read_text(encoding="utf-8"))["title"] == "new"
    assert (plan.target / "0.jpg").read_bytes() == b"old-image"
    assert nfc_path.exists() and nfd_path.exists()


def test_merge_plan_copies_extra_member_to_unmatched_without_deleting_source(tmp_path: Path) -> None:
    nfc_one = tmp_path / "nfc-one"; nfc_two = tmp_path / "nfc-two"; nfd = tmp_path / "nfd"
    for folder in (nfc_one, nfc_two, nfd):
        folder.mkdir(); (folder / "0.jpg").write_bytes(folder.name.encode())
    first = gallery(nfc_one)
    second = GalleryFolder("123", GalleryType.ARCHIVE, "Archive - 123 - Extra", nfc_two, UnicodeStatus.NFC, 1, 0, False, True, False, 1, "now")
    third = GalleryFolder("123", GalleryType.ARCHIVE, "Archive - 123 - NFD", nfd, UnicodeStatus.NFD, 1, 0, False, True, False, 1, "now")
    service = UnicodeOperationService()
    plans = service.build_merge_plans([first, second, third], tmp_path / "result")
    unmatched = next(item for item in plans if item.operation is UnicodeOperationType.COPY_UNMATCHED)
    service.execute(unmatched, tmp_path / "backup")
    assert unmatched.target.parent.name == "NFC"
    assert unmatched.target.is_dir() and unmatched.source.is_dir()
