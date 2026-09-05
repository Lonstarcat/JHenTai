from __future__ import annotations

from PySide6.QtWidgets import QVBoxLayout, QWidget

from app.ui.components import EmptyState, PageHeader


class PlaceholderPage(QWidget):
    def __init__(self, title: str) -> None:
        super().__init__()
        self.setObjectName("PageRoot")
        layout = QVBoxLayout(self)
        layout.setContentsMargins(28, 26, 28, 26)
        layout.setSpacing(20)
        layout.addWidget(PageHeader(title, "此模块将在后续开发阶段逐步开放"))
        layout.addWidget(
            EmptyState("功能尚未开放", "当前阶段专注于安全扫描与画廊状态检查。"),
            1,
        )
