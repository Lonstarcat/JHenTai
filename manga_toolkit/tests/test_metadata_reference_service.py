import json
from pathlib import Path

from app.services.metadata_reference_service import MetadataReferenceService


def test_reads_metadata_and_ametadata_as_separate_sources(tmp_path: Path) -> None:
    (tmp_path / "metadata").write_text(
        json.dumps({"gallery": {"gid": 100, "token": "abc123", "title": "Normal"}}),
        encoding="utf-8",
    )
    (tmp_path / "ametadata").write_text(
        json.dumps({"gid": 200, "token": "def456", "title": "Archive"}),
        encoding="utf-8",
    )

    references = MetadataReferenceService().read_references(tmp_path)

    assert [(item.source, item.gid, item.token) for item in references] == [
        ("metadata", 100, "abc123"),
        ("ametadata", 200, "def456"),
    ]


def test_normal_gallery_reads_only_metadata_when_both_exist(tmp_path: Path) -> None:
    folder = tmp_path / "100 - Normal title"
    folder.mkdir()
    (folder / "metadata").write_text(
        json.dumps({"gallery": {"gid": 100, "token": "normal123"}}),
        encoding="utf-8",
    )
    (folder / "ametadata").write_text(
        json.dumps({"gid": 200, "token": "archive456"}),
        encoding="utf-8",
    )

    references = MetadataReferenceService().read_references(folder)

    assert [(item.source, item.gid) for item in references] == [("metadata", 100)]


def test_archive_gallery_reads_only_ametadata_when_both_exist(tmp_path: Path) -> None:
    folder = tmp_path / "Archive - 200 - Archive title"
    folder.mkdir()
    (folder / "metadata").write_text(
        json.dumps({"gallery": {"gid": 100, "token": "normal123"}}),
        encoding="utf-8",
    )
    (folder / "ametadata").write_text(
        json.dumps({"gid": 200, "token": "archive456"}),
        encoding="utf-8",
    )

    references = MetadataReferenceService().read_references(folder)

    assert [(item.source, item.gid) for item in references] == [("ametadata", 200)]


def test_archive_cbz_reads_only_ametadata_when_both_exist(tmp_path: Path) -> None:
    import zipfile

    archive_path = tmp_path / "Archive - 200 - Archive title.cbz"
    with zipfile.ZipFile(archive_path, "w") as archive:
        archive.writestr("metadata", json.dumps({"gallery": {"gid": 100, "token": "normal123"}}))
        archive.writestr("ametadata", json.dumps({"gid": 200, "token": "archive456"}))

    references = MetadataReferenceService().read_references(archive_path)

    assert [(item.source, item.gid) for item in references] == [("ametadata", 200)]


def test_reads_gid_and_token_from_gallery_url(tmp_path: Path) -> None:
    (tmp_path / "metadata").write_text(
        json.dumps({"gallery": {"galleryUrl": "https://exhentai.org/g/12345/a1b2c3d4e5/"}}),
        encoding="utf-8",
    )
    reference = MetadataReferenceService().read_references(tmp_path)[0]
    assert reference.gid == 12345
    assert reference.token == "a1b2c3d4e5"


def test_metadata_missing_gid(tmp_path: Path) -> None:
    (tmp_path / "metadata").write_text(json.dumps({"gallery": {"token": "abc"}}), encoding="utf-8")
    reference = MetadataReferenceService().read_references(tmp_path)[0]
    assert reference.gid is None
    assert reference.parse_error == "metadata 缺少 gid"


def test_metadata_missing_token(tmp_path: Path) -> None:
    (tmp_path / "ametadata").write_text(json.dumps({"gid": 123}), encoding="utf-8")
    reference = MetadataReferenceService().read_references(tmp_path)[0]
    assert reference.token is None
    assert reference.parse_error == "metadata 缺少 token"


def test_malformed_metadata_json(tmp_path: Path) -> None:
    (tmp_path / "metadata").write_text("{", encoding="utf-8")
    reference = MetadataReferenceService().read_references(tmp_path)[0]
    assert reference.gid is None
    assert reference.parse_error
