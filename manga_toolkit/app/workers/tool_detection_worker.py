from __future__ import annotations

from PySide6.QtCore import QObject, Signal, Slot

from app.services.tool_detection_service import ToolDetectionService


class ToolDetectionWorker(QObject):
    detected = Signal(object)
    finished = Signal()

    def __init__(self, configured_paths: dict[str, str]) -> None:
        super().__init__()
        self._configured_paths = configured_paths

    @Slot()
    def run(self) -> None:
        try:
            self.detected.emit(ToolDetectionService().detect(self._configured_paths))
        finally:
            self.finished.emit()
