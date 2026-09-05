from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QLabel


class StatusBadge(QLabel):
    def __init__(self, text: str = "", status: str = "neutral") -> None:
        super().__init__(text)
        self.setProperty("badge", True)
        self.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.set_status(status)

    def set_status(self, status: str, text: str | None = None) -> None:
        self.setProperty("status", status)
        if text is not None:
            self.setText(text)
        self.style().unpolish(self)
        self.style().polish(self)
