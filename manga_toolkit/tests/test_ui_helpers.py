from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QSortFilterProxyModel, Qt
from PySide6.QtWidgets import QApplication, QStyle

from app.models.gallery_folder import GalleryFolder, GalleryStorage, GalleryType, UnicodeStatus
from app.ui.feature_table_model import FeatureTableModel
from app.ui.components.filter_bar import FilterBar
from app.ui.components.sidebar import NavigationItem, Sidebar
from app.ui.pages.dashboard_page import DashboardPage
from app.ui.table_interactions import TableInteractions


def _application() -> QApplication:
    return QApplication.instance() or QApplication([])


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


def test_sidebar_compact_mode_preserves_rows_and_selection() -> None:
    _application()
    items = (
        NavigationItem("仪表盘", QStyle.StandardPixmap.SP_ComputerIcon),
        NavigationItem("库扫描", QStyle.StandardPixmap.SP_DirHomeIcon),
    )
    sidebar = Sidebar(items)
    sidebar.set_current_index(1)
    sidebar.set_compact(True)
    assert sidebar.navigation.count() == 2
    assert sidebar.navigation.currentRow() == 1
    assert sidebar.navigation.item(1).text() == ""
    assert sidebar.navigation.item(1).toolTip() == "库扫描"
    sidebar.set_compact(False)
    assert sidebar.navigation.item(1).text() == "库扫描"


def test_filter_bar_reset_and_result_summary() -> None:
    app = _application()
    source = FeatureTableModel((("值", lambda row: row),))
    proxy = QSortFilterProxyModel()
    proxy.setSourceModel(source)
    proxy.setFilterKeyColumn(0)
    filters = FilterBar()
    filters.bind_model(proxy)
    source.set_rows(["alpha", "beta", "gamma"])
    proxy.setFilterFixedString("alpha")
    app.processEvents()
    assert filters.result_count.text() == "1 / 3 项"
    filters.search.setText("alpha")
    assert not filters.reset_button.isHidden()
    filters.reset()
    assert filters.search.text() == ""


def test_dashboard_responsive_relayout_reuses_cards() -> None:
    _application()
    dashboard = DashboardPage()
    total_card = dashboard.total
    dashboard.set_width_class("compact")
    assert dashboard.total is total_card
    assert dashboard.overview_grid.indexOf(total_card) >= 0
    assert dashboard._column_count == 2
    dashboard.set_width_class("medium")
    assert dashboard.total is total_card
    assert dashboard._column_count == 3
