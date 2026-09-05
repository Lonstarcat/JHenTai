from __future__ import annotations

from PySide6.QtWidgets import QFrame, QHBoxLayout, QLabel, QProgressBar, QVBoxLayout


class TaskProgress(QFrame):
    def __init__(self, title: str, idle_text: str) -> None:
        super().__init__()
        self.setObjectName("TaskProgress")
        layout = QVBoxLayout(self)
        layout.setContentsMargins(14, 12, 14, 12)
        layout.setSpacing(8)
        row = QHBoxLayout()
        self.title = QLabel(title)
        self.title.setObjectName("SectionTitle")
        self.status = QLabel(idle_text)
        self.status.setObjectName("SecondaryText")
        row.addWidget(self.title)
        row.addStretch(1)
        row.addWidget(self.status)
        self.progress = QProgressBar()
        self.progress.setRange(0, 100)
        layout.addLayout(row)
        layout.addWidget(self.progress)

    def update_progress(self, current: int, total: int, text: str) -> None:
        self.progress.setMaximum(max(total, 1))
        self.progress.setValue(current)
        self.status.setText(text)
