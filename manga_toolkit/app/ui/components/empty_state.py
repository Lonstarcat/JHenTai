from __future__ import annotations

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QLabel, QPushButton, QVBoxLayout, QWidget


class EmptyState(QWidget):
    def __init__(self, title: str, description: str, action_text: str = "") -> None:
        super().__init__()
        layout = QVBoxLayout(self)
        layout.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.setSpacing(10)
        self.title = QLabel(title)
        self.title.setObjectName("SectionTitle")
        self.title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.description = QLabel(description)
        self.description.setObjectName("EmptyDescription")
        self.description.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.description.setWordWrap(True)
        self.action = QPushButton(action_text)
        self.action.setProperty("variant", "primary")
        self.action.setVisible(bool(action_text))
        layout.addStretch(1)
        layout.addWidget(self.title)
        layout.addWidget(self.description)
        layout.addWidget(self.action, 0, Qt.AlignmentFlag.AlignCenter)
        layout.addStretch(1)
