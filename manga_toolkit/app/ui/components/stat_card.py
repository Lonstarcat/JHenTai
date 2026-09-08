from __future__ import annotations

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QKeyEvent, QMouseEvent
from PySide6.QtWidgets import QFrame, QLabel, QVBoxLayout


class StatCard(QFrame):
    clicked = Signal()

    def __init__(
        self,
        label: str,
        value: str = "0",
        hint: str = "",
        clickable: bool = False,
        tone: str = "neutral",
    ) -> None:
        super().__init__()
        self.setObjectName("Card")
        self.setMinimumHeight(92)
        self.setProperty("clickable", clickable)
        self.setProperty("tone", tone)
        if clickable:
            self.setCursor(Qt.CursorShape.PointingHandCursor)
            self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
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

    def set_tone(self, tone: str) -> None:
        if self.property("tone") == tone:
            return
        self.setProperty("tone", tone)
        self.style().unpolish(self)
        self.style().polish(self)

    def mouseReleaseEvent(self, event: QMouseEvent) -> None:
        if self.property("clickable") and event.button() == Qt.MouseButton.LeftButton:
            self.clicked.emit()
        super().mouseReleaseEvent(event)

    def keyReleaseEvent(self, event: QKeyEvent) -> None:
        if self.property("clickable") and event.key() in (Qt.Key.Key_Return, Qt.Key.Key_Enter, Qt.Key.Key_Space):
            self.clicked.emit()
            event.accept()
            return
        super().keyReleaseEvent(event)
