from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QObject, Signal, Slot

from app.models.library_analysis import DuplicateGroup, UnicodeAnalysisResult
from app.services.report_service import ReportService


class DuplicateReportWorker(QObject):
    succeeded = Signal(str)
    failed = Signal(str)
    finished = Signal()

    def __init__(self, groups: list[DuplicateGroup], destination: Path) -> None:
        super().__init__()
        self._groups = groups
        self._destination = destination

    @Slot()
    def run(self) -> None:
        try:
            ReportService().export_duplicates(self._groups, self._destination)
            self.succeeded.emit(str(self._destination))
        except Exception as error:
            self.failed.emit(f"导出重复检测报告失败：{error}")
        finally:
            self.finished.emit()


class UnicodeReportWorker(QObject):
    succeeded = Signal(str)
    failed = Signal(str)
    finished = Signal()

    def __init__(self, result: UnicodeAnalysisResult, destination: Path) -> None:
        super().__init__()
        self._result = result
        self._destination = destination

    @Slot()
    def run(self) -> None:
        try:
            ReportService().export_unicode(self._result, self._destination)
            self.succeeded.emit(str(self._destination))
        except Exception as error:
            self.failed.emit(f"导出 Unicode 报告失败：{error}")
        finally:
            self.finished.emit()
