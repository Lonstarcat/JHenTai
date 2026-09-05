from __future__ import annotations

from PySide6.QtCore import Signal
from PySide6.QtWidgets import QGridLayout, QLabel, QVBoxLayout, QWidget

from app.ui.components import PageHeader, StatCard


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
        self.duplicates = StatCard("重复 ID", "—", clickable=True)
        self.nfd = StatCard("NFD", "—", clickable=True)
        self.issues = StatCard("扫描异常", clickable=True)
        self.missing_comic_info = StatCard("缺少 ComicInfo", "—", clickable=True)
        self.updates = StatCard("有新版本", "—", clickable=True)
        for index, card in enumerate(
            (self.total, self.duplicates, self.nfd, self.issues, self.missing_comic_info, self.updates)
        ):
            cards.addWidget(card, index // 3, index % 3)
        self.total.clicked.connect(lambda: self.navigate_requested.emit("库扫描"))
        self.duplicates.clicked.connect(lambda: self.navigate_requested.emit("重复检测"))
        self.nfd.clicked.connect(lambda: self.navigate_requested.emit("Unicode 工具"))
        self.issues.clicked.connect(lambda: self.navigate_requested.emit("库扫描"))
        self.missing_comic_info.clicked.connect(lambda: self.navigate_requested.emit("库扫描"))
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
        self.issues.set_value(issues)
        if missing_comic_info is not None:
            self.missing_comic_info.set_value(missing_comic_info)

    def update_gallery_counts(self, updates: int) -> None:
        self.updates.set_value(updates)

    def update_duplicate_count(self, groups: int) -> None:
        self.duplicates.set_value(groups)

    def update_nfd_count(self, count: int) -> None:
        self.nfd.set_value(count)
