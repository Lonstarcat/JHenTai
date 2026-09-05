from __future__ import annotations

import json
import zipfile
from dataclasses import replace
from pathlib import Path

from app.models.gallery_folder import GalleryFolder, GalleryStorage, GalleryType, UnicodeStatus
from app.models.toolkit_features import CbzStatus, PlanStatus
from app.services.cbz_service import CbzService
from app.services.directory_check_service import DirectoryCheckService
from app.services.library_compare_service import LibraryCompareService
from app.services.metadata_service import MetadataService
from app.services.name_organizer_service import NameOrganizerService, folder_title


def gallery(path: Path, gallery_id: str = "123", kind: GalleryType = GalleryType.NORMAL, count: int = 3) -> GalleryFolder:
    return GalleryFolder(gallery_id, kind, path.name, path, UnicodeStatus.NFC, count, 0, True, True, True, 1, "now")


def test_name_plan_uses_long_name_without_overwrite(tmp_path: Path) -> None:
    short = tmp_path / "123 - A"; long = tmp_path / "123 - A long"
    short.mkdir(); long.mkdir()
    plans = NameOrganizerService().build_plans([gallery(short), gallery(long)])
    assert len(plans) == 1
    assert plans[0].target == tmp_path / long.name
    assert plans[0].status is PlanStatus.CONFLICT


def test_name_classification_plan_separates_short_and_long(tmp_path: Path) -> None:
    short = tmp_path / "123 - A"; long = tmp_path / "123 - A long"
    plans = NameOrganizerService().build_classification_plans([gallery(short), gallery(long)], tmp_path / "out")
    assert {plan.target.parent.name for plan in plans} == {"Short", "Long"}


def test_name_sync_plan_uses_long_folder_name(tmp_path: Path) -> None:
    short = tmp_path / "Normal_ID" / "Short" / "123 - A"
    long = tmp_path / "Normal_ID" / "Long" / "123 - A long"
    short.mkdir(parents=True); long.mkdir(parents=True)
    plans = NameOrganizerService().build_sync_plans(tmp_path)
    assert len(plans) == 1
    assert plans[0].target.name == long.name
    assert plans[0].status is PlanStatus.READY


def test_folder_title_handles_normal_and_archive() -> None:
    assert folder_title("123 - Title") == "Title"
    assert folder_title("Archive - 123 - Title") == "Title"


def test_metadata_group_name_updates_correct_level_and_backs_up(tmp_path: Path) -> None:
    folder = tmp_path / "123 - Title"; folder.mkdir()
    path = folder / "metadata"
    path.write_text(json.dumps({"gallery": {"title": "Title", "groupName": "old"}}), encoding="utf-8")
    backup = MetadataService().update_group_name(folder, "metadata", "下载", tmp_path / "backup")
    assert json.loads(path.read_text(encoding="utf-8"))["gallery"]["groupName"] == "下载"
    assert "groupName" not in json.loads(path.read_text(encoding="utf-8"))
    assert json.loads(backup.read_text(encoding="utf-8"))["gallery"]["groupName"] == "old"


def test_metadata_title_difference_classification() -> None:
    service = MetadataService()
    assert service._classify_title("A  B", "A B")[0] == "空格差异"
    assert service._classify_title("Ａ", "A")[0] == "全角半角差异"
    assert service._classify_title("Long title", "Long")[0] == "文本截断"


def test_directory_check_reports_only_unexpected_entries(tmp_path: Path) -> None:
    folder = tmp_path / "123 - Title"; folder.mkdir()
    (folder / "0.jpg").write_bytes(b"x"); (folder / "metadata").write_text("{}")
    (folder / "note.txt").write_text("x"); (folder / "nested").mkdir()
    issues = DirectoryCheckService().check([gallery(folder)])
    assert {item.issue_type for item in issues} == {"异常文件", "子文件夹"}


def test_directory_check_supports_cbz_items(tmp_path: Path) -> None:
    path = tmp_path / "123 - Title.cbz"
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("0.jpg", b"x")
        archive.writestr("note.txt", "x")
    item = replace(gallery(path), storage_type=GalleryStorage.CBZ)
    issues = DirectoryCheckService().check([item])
    assert {issue.issue_type for issue in issues} == {"CBZ 异常文件"}


def test_metadata_analysis_reads_cbz_without_treating_it_as_folder(tmp_path: Path) -> None:
    path = tmp_path / "123 - Title.cbz"
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("metadata", json.dumps({"gallery": {"title": "Title", "groupName": "下载"}}))
        archive.writestr("ametadata", json.dumps({"title": "Title", "groupName": "归档"}))
    item = replace(gallery(path), storage_type=GalleryStorage.CBZ)
    results = MetadataService().analyze([item])
    assert [result.status for result in results] == ["正常", "正常"]
    assert all("只读" in result.detail for result in results)


def test_library_compare_respects_type_by_default(tmp_path: Path) -> None:
    a = gallery(tmp_path / "123 - A")
    b = gallery(tmp_path / "Archive - 123 - A", kind=GalleryType.ARCHIVE)
    strict = LibraryCompareService().compare([a], [b])
    cross = LibraryCompareService().compare([a], [b], cross_type=True)
    assert {row.status for row in strict} == {"仅 A 存在", "仅 B 存在"}
    assert len(cross) == 1


def test_cbz_validation_detects_valid_and_nested_archives(tmp_path: Path) -> None:
    folder = tmp_path / "123 - Title"; folder.mkdir()
    item = gallery(folder, count=3)
    valid = tmp_path / "valid.cbz"
    with zipfile.ZipFile(valid, "w") as archive:
        archive.writestr("0.jpg", b"x"); archive.writestr("metadata", "{}"); archive.writestr("ComicInfo.xml", "<ComicInfo/>")
    assert CbzService().check(item, valid).status is CbzStatus.VALID
    nested = tmp_path / "nested.cbz"
    with zipfile.ZipFile(nested, "w") as archive:
        archive.writestr("Title/0.jpg", b"x"); archive.writestr("Title/metadata", "{}"); archive.writestr("Title/ComicInfo.xml", "x")
    assert CbzService().check(item, nested).status is CbzStatus.NESTED_ROOT
