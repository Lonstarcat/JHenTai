from __future__ import annotations

import time

from PySide6.QtWidgets import QFrame, QHBoxLayout, QLabel, QProgressBar, QVBoxLayout


class TaskProgress(QFrame):
    def __init__(self, title: str, idle_text: str) -> None:
        super().__init__()
        self.setObjectName("TaskProgress")
        self._started_at: float | None = None
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
        if self._started_at is None:
            self._started_at = time.monotonic()
        self.progress.setMaximum(max(total, 1))
        self.progress.setValue(current)
        self.status.setText(f"{text} · 已用 {self._elapsed_text()}")

    def begin(self, text: str) -> None:
        self._started_at = time.monotonic()
        self.progress.setMaximum(1)
        self.progress.setValue(0)
        self.status.setText(f"{text} · 已用 00:00")

    def finish(self) -> None:
        if self._started_at is None:
            return
        current = self.status.text()
        if " · 已用 " in current:
            current = current.rsplit(" · 已用 ", 1)[0]
        self.status.setText(f"{current} · 耗时 {self._elapsed_text()}")
        self._started_at = None

    def _elapsed_text(self) -> str:
        elapsed = max(0, int(time.monotonic() - (self._started_at or time.monotonic())))
        minutes, seconds = divmod(elapsed, 60)
        hours, minutes = divmod(minutes, 60)
        return f"{hours:02d}:{minutes:02d}:{seconds:02d}" if hours else f"{minutes:02d}:{seconds:02d}"
