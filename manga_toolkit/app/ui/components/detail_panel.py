from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QFrame, QLabel, QScrollArea, QVBoxLayout, QWidget


class DetailPanel(QFrame):
    def __init__(self, empty_text: str = "选择一行查看详情") -> None:
        super().__init__()
        self.setObjectName("Panel")
        self.setMinimumWidth(280)
        self.setMaximumWidth(380)
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        content = QWidget()
        content.setObjectName("DetailContent")
        self._layout = QVBoxLayout(content)
        self._layout.setContentsMargins(18, 18, 18, 18)
        self._layout.setSpacing(8)
        self._title = QLabel(empty_text)
        self._title.setObjectName("SectionTitle")
        self._title.setWordWrap(True)
        self._layout.addWidget(self._title)
        self._layout.addStretch(1)
        scroll.setWidget(content)
        outer.addWidget(scroll)

    def set_details(self, title: str, fields: list[tuple[str, str]]) -> None:
        while self._layout.count():
            item = self._layout.takeAt(0)
            widget = item.widget()
            if widget is not None:
                widget.hide()
                widget.setParent(None)
                widget.deleteLater()
        self._title = QLabel(title)
        self._title.setObjectName("SectionTitle")
        self._title.setWordWrap(True)
        self._layout.addWidget(self._title)
        self._layout.addSpacing(8)
        for label, value in fields:
            name = QLabel(label)
            name.setObjectName("FieldLabel")
            data = QLabel(value or "—")
            data.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
            data.setWordWrap(True)
            self._layout.addWidget(name)
            self._layout.addWidget(data)
            self._layout.addSpacing(5)
        self._layout.addStretch(1)
