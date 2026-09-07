from __future__ import annotations

from PySide6.QtCore import Signal
from PySide6.QtWidgets import QGridLayout, QLabel, QVBoxLayout, QWidget

from app.ui.components import PageHeader, StatCard
from app.models.gallery_folder import GalleryFolder, GalleryStorage, GalleryType, UnicodeStatus


class DashboardPage(QWidget):
    navigate_requested = Signal(str)

    def __init__(self) -> None:
        super().__init__()
        self.setObjectName("PageRoot")
        layout = QVBoxLayout(self)
        layout.setContentsMargins(28, 26, 28, 26)
        layout.setSpacing(20)
        layout.addWidget(PageHeader("仪表盘", "快速了解当前漫画库状态与需要处理的项目"))

        section = QLabel("库概览")
        section.setObjectName("SectionTitle")
        layout.addWidget(section)
        cards = QGridLayout()
        cards.setHorizontalSpacing(14)
        cards.setVerticalSpacing(14)
        self.total = StatCard("漫画总数", clickable=True)
        self.normal = StatCard("Normal", "—", clickable=True)
        self.archive = StatCard("Archive", "—", clickable=True)
        self.nfc = StatCard("NFC", "—", clickable=True)
        self.duplicates = StatCard("重复 ID", "—", clickable=True)
        self.nfd = StatCard("NFD", "—", clickable=True)
        self.issues = StatCard("扫描异常", clickable=True)
        self.missing_metadata = StatCard("缺少 Metadata", "—", clickable=True)
        self.missing_comic_info = StatCard("缺少 ComicInfo", "—", clickable=True)
        self.cbz_count = StatCard("CBZ 数量", "—", clickable=True)
        self.invalid_cbz = StatCard("异常 CBZ", "—", clickable=True)
        self.updates = StatCard("有新版本", "—", clickable=True)
        for index, card in enumerate(
            (
                self.total, self.normal, self.archive, self.nfc,
                self.nfd, self.duplicates, self.missing_metadata, self.missing_comic_info,
                self.cbz_count, self.invalid_cbz, self.issues, self.updates,
            )
        ):
            cards.addWidget(card, index // 4, index % 4)
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
        layout.addLayout(cards)
        hint = QLabel("所有扫描和远程检查默认只分析数据，不会修改漫画文件。")
        hint.setObjectName("SecondaryText")
        layout.addWidget(hint)
        layout.addStretch(1)

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
        self.issues.set_value(issues)
        if missing_comic_info is not None:
            self.missing_comic_info.set_value(missing_comic_info)

    def update_inventory(self, galleries: list[GalleryFolder]) -> None:
        self.total.set_value(len(galleries))
        self.normal.set_value(sum(item.gallery_type is GalleryType.NORMAL for item in galleries))
        self.archive.set_value(sum(item.gallery_type is GalleryType.ARCHIVE for item in galleries))
        self.nfc.set_value(sum(item.unicode_status is UnicodeStatus.NFC for item in galleries))
        self.nfd.set_value(sum(item.unicode_status is UnicodeStatus.NFD for item in galleries))
        self.missing_metadata.set_value(sum(
            (item.gallery_type is GalleryType.NORMAL and not item.has_metadata)
            or (item.gallery_type is GalleryType.ARCHIVE and not item.has_ametadata)
            or (item.gallery_type is GalleryType.UNKNOWN and not item.has_metadata and not item.has_ametadata)
            for item in galleries
        ))
        self.missing_comic_info.set_value(sum(not item.has_comic_info for item in galleries))
        self.cbz_count.set_value(sum(item.storage_type is GalleryStorage.CBZ for item in galleries))

    def update_cbz_counts(self, total: int, invalid: int) -> None:
        self.cbz_count.set_value(total)
        self.invalid_cbz.set_value(invalid)

    def update_gallery_counts(self, updates: int) -> None:
        self.updates.set_value(updates)

    def update_duplicate_count(self, groups: int) -> None:
        self.duplicates.set_value(groups)

    def update_nfd_count(self, count: int) -> None:
        self.nfd.set_value(count)
