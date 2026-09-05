from __future__ import annotations

import threading
from pathlib import Path

from PySide6.QtCore import QObject, Signal, Slot

from app.services.database_service import DatabaseService
from app.services.duplicate_detection_service import DuplicateDetectionService
from app.services.unicode_analysis_service import UnicodeAnalysisService


class DuplicateAnalysisWorker(QObject):
    progress = Signal(int, int, str)
    completed = Signal(list, bool)
    failed = Signal(str)
    finished = Signal()

    def __init__(
        self,
        database: DatabaseService,
        root: Path,
        normal_normal: bool,
        archive_archive: bool,
        normal_archive: bool,
    ) -> None:
        super().__init__()
        self._database = database
        self._root = root
        self._modes = (normal_normal, archive_archive, normal_archive)
        self._cancel = threading.Event()

    def request_cancel(self) -> None:
        self._cancel.set()

    @Slot()
    def run(self) -> None:
        try:
            galleries = self._database.list_galleries(self._root)
            groups = DuplicateDetectionService().detect(
                galleries,
                *self._modes,
                on_progress=self.progress.emit,
                is_cancelled=self._cancel.is_set,
            )
            self.completed.emit(groups, self._cancel.is_set())
        except (OSError, ValueError) as error:
            self.failed.emit(str(error))
        except Exception as error:
            self.failed.emit(f"重复 ID 分析失败：{error}")
        finally:
            self.finished.emit()


class UnicodeAnalysisWorker(QObject):
    progress = Signal(int, int, str)
    completed = Signal(object, bool)
    failed = Signal(str)
    finished = Signal()

    def __init__(self, database: DatabaseService, root: Path) -> None:
        super().__init__()
        self._database = database
        self._root = root
        self._cancel = threading.Event()

    def request_cancel(self) -> None:
        self._cancel.set()

    @Slot()
    def run(self) -> None:
        try:
            result = UnicodeAnalysisService().analyze(
                self._database.list_galleries(self._root),
                on_progress=self.progress.emit,
                is_cancelled=self._cancel.is_set,
            )
            self.completed.emit(result, self._cancel.is_set())
        except (OSError, ValueError) as error:
            self.failed.emit(str(error))
        except Exception as error:
            self.failed.emit(f"Unicode 分析失败：{error}")
        finally:
            self.finished.emit()
