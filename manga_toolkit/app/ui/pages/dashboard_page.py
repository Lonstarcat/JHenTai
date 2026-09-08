from __future__ import annotations

from PySide6.QtCore import Signal
from PySide6.QtWidgets import QGridLayout, QLabel, QScrollArea, QVBoxLayout, QWidget

from app.ui.components import PageHeader, StatCard
from app.models.gallery_folder import GalleryFolder, GalleryStorage, GalleryType, UnicodeStatus


class DashboardPage(QWidget):
    navigate_requested = Signal(str)

    def __init__(self) -> None:
        super().__init__()
        self.setObjectName("PageRoot")
        outer_layout = QVBoxLayout(self)
        outer_layout.setContentsMargins(28, 26, 28, 26)
        scroll = QScrollArea()
        scroll.setObjectName("DashboardScroll")
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QScrollArea.Shape.NoFrame)
        content = QWidget()
        content.setObjectName("DashboardContent")
        layout = QVBoxLayout(content)
        layout.setContentsMargins(0, 0, 4, 0)
        layout.setSpacing(20)
        layout.addWidget(PageHeader("仪表盘", "快速了解当前漫画库状态与需要处理的项目"))

        section = QLabel("库概览")
        section.setObjectName("SectionTitle")
        layout.addWidget(section)
        self.overview_grid = QGridLayout()
        self.overview_grid.setHorizontalSpacing(14)
        self.overview_grid.setVerticalSpacing(14)
        self.total = StatCard("漫画总数", clickable=True)
        self.normal = StatCard("Normal", "—", clickable=True)
        self.archive = StatCard("Archive", "—", clickable=True)
        self.cbz_count = StatCard("CBZ 数量", "—", clickable=True)
        self.nfc = StatCard("NFC", "—", "名称编码质量", clickable=True)
        self.overview_cards = (self.total, self.normal, self.archive, self.cbz_count, self.nfc)

        attention_title = QLabel("需要关注")
        attention_title.setObjectName("SectionTitle")
        layout.addLayout(self.overview_grid)
        layout.addWidget(attention_title)
        self.attention_grid = QGridLayout()
        self.attention_grid.setHorizontalSpacing(14)
        self.attention_grid.setVerticalSpacing(14)
        self.duplicates = StatCard("重复 ID", "—", clickable=True, tone="attention")
        self.nfd = StatCard("NFD", "—", clickable=True, tone="attention")
        self.issues = StatCard("扫描异常", clickable=True, tone="attention")
        self.missing_metadata = StatCard("缺少 Metadata", "—", clickable=True, tone="attention")
        self.missing_comic_info = StatCard("缺少 ComicInfo", "—", clickable=True, tone="attention")
        self.invalid_cbz = StatCard("异常 CBZ", "—", clickable=True)
        self.invalid_cbz.set_tone("attention")
        self.updates = StatCard("有新版本", "—", clickable=True, tone="info")
        self.attention_cards = (
            self.duplicates, self.nfd, self.missing_metadata, self.missing_comic_info,
            self.invalid_cbz, self.issues, self.updates,
        )
        self.total.clicked.connect(lambda: self.navigate_requested.emit("库扫描"))
        self.normal.clicked.connect(lambda: self.navigate_requested.emit("库扫描"))
        self.archive.clicked.connect(lambda: self.navigate_requested.emit("库扫描"))
        self.nfc.clicked.connect(lambda: self.navigate_requested.emit("Unicode 工具"))
        self.duplicates.clicked.connect(lambda: self.navigate_requested.emit("重复检测"))
        self.nfd.clicked.connect(lambda: self.navigate_requested.emit("Unicode 工具"))
        self.issues.clicked.connect(lambda: self.navigate_requested.emit("库扫描"))
        self.missing_metadata.clicked.connect(lambda: self.navigate_requested.emit("Metadata"))
        self.missing_comic_info.clicked.connect(lambda: self.navigate_requested.emit("库扫描"))
        self.cbz_count.clicked.connect(lambda: self.navigate_requested.emit("CBZ 工具"))
        self.invalid_cbz.clicked.connect(lambda: self.navigate_requested.emit("CBZ 工具"))
        self.updates.clicked.connect(lambda: self.navigate_requested.emit("画廊状态"))
        layout.addLayout(self.attention_grid)
        self._column_count = 0
        self.set_width_class("wide")
        hint = QLabel("所有扫描和远程检查默认只分析数据，不会修改漫画文件。")
        hint.setObjectName("SecondaryText")
        layout.addWidget(hint)
        layout.addStretch(1)
        scroll.setWidget(content)
        outer_layout.addWidget(scroll)

    def set_width_class(self, width_class: str) -> None:
        columns = 4 if width_class == "wide" else 3 if width_class == "medium" else 2
        if columns == self._column_count:
            return
        self._column_count = columns
        self._relayout(self.overview_grid, self.overview_cards, columns)
        self._relayout(self.attention_grid, self.attention_cards, columns)

    @staticmethod
    def _relayout(grid: QGridLayout, cards: tuple[StatCard, ...], columns: int) -> None:
        while grid.count():
            grid.takeAt(0)
        for index, card in enumerate(cards):
            grid.addWidget(card, index // columns, index % columns)

    @staticmethod
    def _update_attention(card: StatCard, value: int, tone: str = "attention") -> None:
        card.set_value(value)
        card.set_tone(tone if value else "neutral")

    def update_summary(
        self,
        total: int,
        normal: int,
        archive: int,
        issues: int,
        missing_comic_info: int | None = None,
    ) -> None:
        self.total.set_value(total)
        self.normal.set_value(normal)
        self.archive.set_value(archive)
        self._update_attention(self.issues, issues)
        if missing_comic_info is not None:
            self._update_attention(self.missing_comic_info, missing_comic_info)

    def update_inventory(self, galleries: list[GalleryFolder]) -> None:
        self.total.set_value(len(galleries))
        self.normal.set_value(sum(item.gallery_type is GalleryType.NORMAL for item in galleries))
        self.archive.set_value(sum(item.gallery_type is GalleryType.ARCHIVE for item in galleries))
        self.nfc.set_value(sum(item.unicode_status is UnicodeStatus.NFC for item in galleries))
        self._update_attention(self.nfd, sum(item.unicode_status is UnicodeStatus.NFD for item in galleries))
        self._update_attention(self.missing_metadata, sum(
            (item.gallery_type is GalleryType.NORMAL and not item.has_metadata)
            or (item.gallery_type is GalleryType.ARCHIVE and not item.has_ametadata)
            or (item.gallery_type is GalleryType.UNKNOWN and not item.has_metadata and not item.has_ametadata)
            for item in galleries
        ))
        self._update_attention(self.missing_comic_info, sum(not item.has_comic_info for item in galleries))
        self.cbz_count.set_value(sum(item.storage_type is GalleryStorage.CBZ for item in galleries))

    def update_cbz_counts(self, total: int, invalid: int) -> None:
        self.cbz_count.set_value(total)
        self._update_attention(self.invalid_cbz, invalid)

    def update_gallery_counts(self, updates: int) -> None:
        self._update_attention(self.updates, updates, "info")

    def update_duplicate_count(self, groups: int) -> None:
        self._update_attention(self.duplicates, groups)

    def update_nfd_count(self, count: int) -> None:
        self._update_attention(self.nfd, count)
