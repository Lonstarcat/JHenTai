from __future__ import annotations

import json
import os
import zipfile
from dataclasses import replace
from pathlib import Path

from app.models.gallery_folder import GalleryFolder, GalleryStorage, GalleryType, UnicodeStatus
from app.models.toolkit_features import CbzStatus, ExistingCbzPolicy, IsolationMode, PlanStatus
from app.services.cbz_service import CbzService
from app.services.cbz_organize_service import CbzOrganizeService
from app.services.directory_check_service import DirectoryCheckService
from app.services.library_compare_service import LibraryCompareService
from app.services.metadata_service import MetadataService
from app.services.name_organizer_service import NameOrganizerService, folder_title
from app.services.isolation_service import IsolationService
from app.services.database_service import DatabaseService
from app.workers.feature_workers import check_cbz


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
    assert service._classify_title("Series: Title", "Series Title")[0] == "冒号差异"
    assert service._classify_title("Title!", "Title")[0] == "感叹号差异"


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
    assert [result.status for result in results] == ["正常"]
    assert results[0].file_name == "metadata"
    assert all("只读" in result.detail for result in results)


def test_metadata_analysis_uses_ametadata_only_for_archive(tmp_path: Path) -> None:
    folder = tmp_path / "Archive - 123 - Title"; folder.mkdir()
    (folder / "metadata").write_text(json.dumps({"gallery": {"title": "Wrong"}}), encoding="utf-8")
    (folder / "ametadata").write_text(json.dumps({"title": "Title", "groupName": "归档"}), encoding="utf-8")
    results = MetadataService().analyze([gallery(folder, kind=GalleryType.ARCHIVE)])
    assert len(results) == 1
    assert results[0].file_name == "ametadata"
    assert results[0].status == "正常"


def test_metadata_backup_can_include_comic_info_and_preserves_mtime(tmp_path: Path) -> None:
    folder = tmp_path / "123 - Title"; folder.mkdir()
    metadata = folder / "metadata"; comic_info = folder / "ComicInfo.xml"
    metadata.write_text("{}", encoding="utf-8"); comic_info.write_text("<ComicInfo/>", encoding="utf-8")
    os.utime(metadata, (100, 100)); os.utime(comic_info, (200, 200))
    backups = MetadataService().backup_files(folder, tmp_path / "backup", include_comic_info=True)
    assert {item.name for item in backups} == {"metadata", "ComicInfo.xml"}
    assert (tmp_path / "backup" / folder.name / "metadata").stat().st_mtime_ns == metadata.stat().st_mtime_ns


def test_library_compare_respects_type_by_default(tmp_path: Path) -> None:
    a = gallery(tmp_path / "123 - A")
    b = gallery(tmp_path / "Archive - 123 - A", kind=GalleryType.ARCHIVE)
    strict = LibraryCompareService().compare([a], [b])
    cross = LibraryCompareService().compare([a], [b], cross_type=True)
    assert {row.status for row in strict} == {"仅 A 存在", "仅 B 存在"}
    assert len(cross) == 1


def test_cross_type_compare_applies_archive_size_threshold(tmp_path: Path) -> None:
    normal = replace(gallery(tmp_path / "123 - A"), folder_size=100 * 1024 * 1024)
    archive = replace(
        gallery(tmp_path / "Archive - 123 - A", kind=GalleryType.ARCHIVE),
        folder_size=51 * 1024 * 1024,
    )
    result = LibraryCompareService().compare([normal], [archive], cross_type=True)
    assert result[0].recommendation == "建议保留 Archive"
    smaller = replace(archive, folder_size=50 * 1024 * 1024)
    result = LibraryCompareService().compare([normal], [smaller], cross_type=True)
    assert result[0].recommendation == "建议保留 Normal"


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


def test_cbz_verify_policy_skips_valid_existing_archive(tmp_path: Path) -> None:
    folder = tmp_path / "123 - Title"; folder.mkdir()
    item = gallery(folder, count=3)
    destination = tmp_path / "Title.cbz"
    with zipfile.ZipFile(destination, "w") as archive:
        archive.writestr("0.jpg", b"x"); archive.writestr("metadata", "{}"); archive.writestr("ComicInfo.xml", "<ComicInfo/>")
    state, backup = CbzService().pack_with_policy(
        tmp_path / "7z.exe", item, destination, 0, ExistingCbzPolicy.VERIFY, tmp_path / "backup"
    )
    assert state == "verified" and backup is None


def test_cbz_rebuild_preserves_old_archive(monkeypatch, tmp_path: Path) -> None:
    folder = tmp_path / "123 - Title"; folder.mkdir()
    item = gallery(folder)
    destination = tmp_path / "Title.cbz"; destination.write_bytes(b"old")

    def fake_pack(self, seven_zip, source, target, compression=0):
        target.write_bytes(b"new")

    monkeypatch.setattr(CbzService, "pack", fake_pack)
    state, backup = CbzService().pack_with_policy(
        tmp_path / "7z.exe", item, destination, 0, ExistingCbzPolicy.REBUILD, tmp_path / "backup"
    )
    assert state == "rebuilt" and backup is not None
    assert destination.read_bytes() == b"new" and backup.read_bytes() == b"old"


def test_comic_info_isolation_copy_and_conflict(tmp_path: Path) -> None:
    folder = tmp_path / "123 - Title"; folder.mkdir(); (folder / "0.jpg").write_bytes(b"x")
    cbz = tmp_path / "123 - Title.cbz"; cbz.write_bytes(b"zip")
    result = CbzService().check(gallery(folder), cbz)
    assert result.status is CbzStatus.DAMAGED
    missing = replace(result, status=CbzStatus.NO_COMIC_INFO)
    service = IsolationService()
    plans = service.build_plans([missing], tmp_path / "folders", tmp_path / "archives")
    assert len(plans) == 2 and all(plan.mode is IsolationMode.COPY for plan in plans)
    for plan in plans:
        service.execute(plan)
        assert plan.source.exists() and plan.target.exists()
    conflicts = service.build_plans([missing], tmp_path / "folders", tmp_path / "archives")
    assert all(plan.status is PlanStatus.CONFLICT for plan in conflicts)


def test_cbz_check_reports_missing_and_extra_archives(tmp_path: Path) -> None:
    root = tmp_path / "library"; output = tmp_path / "cbz"
    folder = root / "123 - Title"; folder.mkdir(parents=True); output.mkdir()
    item = gallery(folder)
    database = DatabaseService(tmp_path / "app.db"); database.initialize()
    database.replace_scan(root, [item], "scan")
    (output / "unmatched.cbz").write_bytes(b"not-a-zip")
    action = check_cbz(database, root, output)
    results = action(lambda *_: None, lambda: False)
    assert {result.status for result in results} == {CbzStatus.MISSING, CbzStatus.EXTRA}


def test_cbz_same_name_directory_organizer_copy_and_conflict(tmp_path: Path) -> None:
    source = tmp_path / "A.cbz"
    source.write_bytes(b"archive")
    service = CbzOrganizeService()
    plans = service.build_plans(tmp_path, IsolationMode.COPY)
    assert len(plans) == 1
    assert plans[0].target == tmp_path / "A" / "A.cbz"
    service.execute(plans[0])
    assert source.exists() and plans[0].target.read_bytes() == b"archive"
    assert service.build_plans(tmp_path, IsolationMode.COPY)[0].status is PlanStatus.CONFLICT


def test_cbz_same_name_directory_organizer_move(tmp_path: Path) -> None:
    source = tmp_path / "B.CBZ"
    source.write_bytes(b"archive")
    plan = CbzOrganizeService().build_plans(tmp_path, IsolationMode.MOVE)[0]
    CbzOrganizeService().execute(plan)
    assert not source.exists()
    assert (tmp_path / "B" / "B.CBZ").exists()
