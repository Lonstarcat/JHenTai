from __future__ import annotations

from PySide6.QtWidgets import QHBoxLayout, QLabel, QVBoxLayout, QWidget


class PageHeader(QWidget):
    def __init__(self, title: str, description: str) -> None:
        super().__init__()
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        text_layout = QVBoxLayout()
        text_layout.setSpacing(4)
        heading = QLabel(title)
        heading.setObjectName("PageTitle")
        subtitle = QLabel(description)
        subtitle.setObjectName("PageDescription")
        text_layout.addWidget(heading)
        text_layout.addWidget(subtitle)
        layout.addLayout(text_layout, 1)
        self.actions = QHBoxLayout()
        self.actions.setSpacing(8)
        layout.addLayout(self.actions)

    def add_action(self, widget: QWidget, primary: bool = False) -> None:
        if primary:
            widget.setProperty("variant", "primary")
        self.actions.addWidget(widget)
