from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QObject, Signal, Slot

from app.models.gallery_status import GalleryStatusRecord
from app.services.report_service import ReportService


class GalleryStatusReportWorker(QObject):
    succeeded = Signal(str)
    failed = Signal(str)
    finished = Signal()

    def __init__(self, records: list[GalleryStatusRecord], destination: Path) -> None:
        super().__init__()
        self._records = records
        self._destination = destination

    @Slot()
    def run(self) -> None:
        try:
            ReportService().export_gallery_status(self._records, self._destination)
            self.succeeded.emit(str(self._destination))
        except (OSError, ValueError) as error:
            self.failed.emit(str(error))
        except Exception as error:  # Worker boundary: surface unexpected library failures.
            self.failed.emit(f"导出报告失败：{error}")
        finally:
            self.finished.emit()
