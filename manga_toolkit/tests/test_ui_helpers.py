from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import Qt

from app.models.gallery_folder import GalleryFolder, GalleryStorage, GalleryType, UnicodeStatus
from app.ui.feature_table_model import FeatureTableModel
from app.ui.table_interactions import TableInteractions


def test_feature_table_sort_and_restore_original_order() -> None:
    model = FeatureTableModel((("值", lambda row: row),))
    model.set_rows([10, 2, 5])
    model.sort(0, Qt.SortOrder.AscendingOrder)
    assert model.rows == [2, 5, 10]
    model.sort(-1)
    assert model.rows == [10, 2, 5]


def test_table_path_extraction_recognizes_cbz_gallery(tmp_path: Path) -> None:
    cbz = tmp_path / "123 - Title.cbz"
    gallery = GalleryFolder(
        gallery_id="123",
        gallery_type=GalleryType.NORMAL,
        folder_name=cbz.stem,
        path=cbz,
        unicode_status=UnicodeStatus.NFC,
        file_count=3,
        folder_size=100,
        has_metadata=True,
        has_ametadata=False,
        has_comic_info=True,
        modified_ns=1,
        scanned_at="now",
        storage_type=GalleryStorage.CBZ,
    )
    paths = TableInteractions._extract_paths(gallery)
    assert paths == [("漫画位置", cbz)]
