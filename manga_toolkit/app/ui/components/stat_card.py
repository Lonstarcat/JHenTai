from __future__ import annotations

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QMouseEvent
from PySide6.QtWidgets import QFrame, QLabel, QVBoxLayout


class StatCard(QFrame):
    clicked = Signal()

    def __init__(self, label: str, value: str = "0", hint: str = "", clickable: bool = False) -> None:
        super().__init__()
        self.setObjectName("Card")
        self.setProperty("clickable", clickable)
        if clickable:
            self.setCursor(Qt.CursorShape.PointingHandCursor)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(18, 16, 18, 16)
        layout.setSpacing(6)
        self.label = QLabel(label)
        self.label.setObjectName("CardLabel")
        self.value = QLabel(value)
        self.value.setObjectName("CardValue")
        self.hint = QLabel(hint)
        self.hint.setObjectName("SecondaryText")
        self.hint.setVisible(bool(hint))
        layout.addWidget(self.label)
        layout.addWidget(self.value)
        layout.addWidget(self.hint)

    def set_value(self, value: int | str) -> None:
        self.value.setText(str(value))

    def mouseReleaseEvent(self, event: QMouseEvent) -> None:
        if self.property("clickable") and event.button() == Qt.MouseButton.LeftButton:
            self.clicked.emit()
        super().mouseReleaseEvent(event)
