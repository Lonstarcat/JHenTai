from __future__ import annotations

from PySide6.QtWidgets import QFrame, QHBoxLayout, QLineEdit, QWidget


class FilterBar(QFrame):
    def __init__(self, placeholder: str = "搜索文件夹名或 ID…") -> None:
        super().__init__()
        self.setObjectName("FilterBar")
        self.layout = QHBoxLayout(self)
        self.layout.setContentsMargins(12, 10, 12, 10)
        self.layout.setSpacing(8)
        self.search = QLineEdit()
        self.search.setPlaceholderText(placeholder)
        self.search.setClearButtonEnabled(True)
        self.search.setMinimumWidth(260)
        self.layout.addWidget(self.search, 1)

    def add_control(self, widget: QWidget) -> None:
        self.layout.addWidget(widget)
