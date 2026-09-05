from __future__ import annotations

import logging
import threading
import uuid
from pathlib import Path

from PySide6.QtCore import QObject, Signal, Slot

from app.models.gallery_folder import GalleryFolder
from app.models.scan_result import ScanResult
from app.services.database_service import DatabaseService
from app.services.scanner_service import LibraryScannerService

logger = logging.getLogger(__name__)


class ScanWorker(QObject):
    progress = Signal(int, int, str)
    batch_ready = Signal(list)
    completed = Signal(int, int, int, bool)
    failed = Signal(str)
    finished = Signal()

    def __init__(self, root: Path, database: DatabaseService) -> None:
        super().__init__()
        self._root = root
        self._database = database
        self._cancel_event = threading.Event()

    def request_cancel(self) -> None:
        self._cancel_event.set()

    @Slot()
    def run(self) -> None:
        try:
            cached = self._database.load_cached(self._root)
            scanner = LibraryScannerService()
            display_batch: list[GalleryFolder] = []

            def emit_result(result: ScanResult) -> None:
                if result.gallery is None:
                    return
                display_batch.append(result.gallery)
                if len(display_batch) >= 200:
                    self.batch_ready.emit(list(display_batch))
                    display_batch.clear()

            results = scanner.scan(
                self._root,
                cached=cached,
                on_progress=self.progress.emit,
                on_result=emit_result,
                is_cancelled=self._cancel_event.is_set,
            )
            galleries: list[GalleryFolder] = []
            issue_count = 0
            for result in results:
                if result.gallery is not None:
                    galleries.append(result.gallery)
                if result.issue is not None:
                    issue_count += 1
            if display_batch:
                self.batch_ready.emit(list(display_batch))

            cancelled = self._cancel_event.is_set()
            if not cancelled:
                self._database.replace_scan(
                    self._root,
                    galleries,
                    scan_token=uuid.uuid4().hex,
                )
            cached_count = sum(gallery.from_cache for gallery in galleries)
            self.completed.emit(len(galleries), issue_count, cached_count, cancelled)
        except (OSError, ValueError) as error:
            logger.exception("Library scan failed")
            self.failed.emit(str(error))
        except Exception as error:  # Qt worker boundary: report unexpected failures.
            logger.exception("Unexpected library scan failure")
            self.failed.emit(f"扫描发生未预期错误：{error}")
        finally:
            self.finished.emit()
