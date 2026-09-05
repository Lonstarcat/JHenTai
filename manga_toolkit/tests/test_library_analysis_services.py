from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

from app.models.gallery_folder import GalleryFolder, GalleryType, UnicodeStatus
from app.models.library_analysis import DuplicateKind
from app.services.duplicate_detection_service import DuplicateDetectionService
from app.services.unicode_analysis_service import UnicodeAnalysisService
from app.services.unicode_service import detect_unicode_status


def gallery(name: str, gallery_type: GalleryType, gallery_id: str | None = "100") -> GalleryFolder:
    return GalleryFolder(
        gallery_id=gallery_id,
        gallery_type=gallery_type,
        folder_name=name,
        path=Path("C:/Manga") / name,
        unicode_status=detect_unicode_status(name),
        file_count=1,
        folder_size=10,
        has_metadata=True,
        has_ametadata=False,
        has_comic_info=True,
        modified_ns=1,
        scanned_at=datetime.now(UTC).isoformat(),
    )


def test_duplicate_detection_modes_are_independent() -> None:
    galleries = [
        gallery("100 - N short", GalleryType.NORMAL),
        gallery("100 - N considerably longer", GalleryType.NORMAL),
        gallery("Archive - 100 - A", GalleryType.ARCHIVE),
        gallery("Archive - 100 - A long", GalleryType.ARCHIVE),
    ]
    service = DuplicateDetectionService()

    same_type = service.detect(galleries)
    cross_type = service.detect(
        galleries,
        normal_normal=False,
        archive_archive=False,
        normal_archive=True,
    )

    assert {group.kind for group in same_type} == {DuplicateKind.NORMAL, DuplicateKind.ARCHIVE}
    assert len(cross_type) == 1
    assert cross_type[0].kind is DuplicateKind.CROSS_TYPE
    assert len(cross_type[0].members) == 4


def test_duplicate_length_roles() -> None:
    groups = DuplicateDetectionService().detect(
        [
            gallery("100 - short", GalleryType.NORMAL),
            gallery("100 - a much longer name", GalleryType.NORMAL),
        ]
    )
    assert [groups[0].length_role(member) for member in groups[0].members] == ["Short", "Long"]


def test_missing_id_is_not_grouped() -> None:
    items = [
        gallery("unknown A", GalleryType.UNKNOWN, None),
        gallery("unknown B", GalleryType.UNKNOWN, None),
    ]
    assert DuplicateDetectionService().detect(items, normal_archive=True) == []


def test_unicode_analysis_detects_nfc_nfd_equivalent_names() -> None:
    nfc = gallery("100 - Café", GalleryType.NORMAL)
    nfd = gallery("100 - Cafe\u0301", GalleryType.NORMAL)

    result = UnicodeAnalysisService().analyze([nfc, nfd])

    assert result.nfc_count == 1
    assert result.nfd_count == 1
    assert len(result.duplicate_groups) == 1
    assert set(result.duplicate_groups[0].members) == {nfc, nfd}


def test_exact_same_names_are_not_unicode_encoding_duplicates() -> None:
    first = gallery("100 - Same", GalleryType.NORMAL)
    second = GalleryFolder(
        **{
            field: getattr(first, field)
            for field in first.__dataclass_fields__
            if field != "path"
        },
        path=Path("D:/Manga/100 - Same"),
    )
    result = UnicodeAnalysisService().analyze([first, second])
    assert result.duplicate_groups == []
