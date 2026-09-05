from __future__ import annotations

import logging
import threading
from pathlib import Path

from PySide6.QtCore import QObject, Signal, Slot

from app.models.gallery_status import GalleryReference, GalleryStatusRecord
from app.services.credential_service import CredentialService
from app.services.database_service import DatabaseService
from app.services.ehentai_api import EhentaiApiClient
from app.services.gallery_cache_service import GalleryCacheService
from app.services.gallery_page_checker import GalleryPageStatusChecker
from app.services.gallery_status_service import (
    GalleryStatusService,
    StatusCheckMode,
    StatusCheckOptions,
)
from app.services.metadata_reference_service import MetadataReferenceService

logger = logging.getLogger(__name__)


class GalleryStatusWorker(QObject):
    progress = Signal(int, int, str)
    batch_ready = Signal(list)
    completed = Signal(int, int, bool)
    failed = Signal(str)
    finished = Signal()

    def __init__(
        self,
        root: Path,
        database: DatabaseService,
        credentials: CredentialService,
        options: StatusCheckOptions,
        mode: StatusCheckMode,
        force_refresh: bool = False,
        selected_references: list[GalleryReference] | None = None,
        cache_only: bool = False,
    ) -> None:
        super().__init__()
        self._root = root
        self._database = database
        self._credentials = credentials
        self._options = options
        self._mode = mode
        self._force_refresh = force_refresh
        self._selected_references = selected_references
        self._cache_only = cache_only
        self._cancel_event = threading.Event()

    def request_cancel(self) -> None:
        self._cancel_event.set()

    @Slot()
    def run(self) -> None:
        api: EhentaiApiClient | None = None
        checker: GalleryPageStatusChecker | None = None
        try:
            cache = GalleryCacheService(self._database.database_path)
            if self._cache_only:
                records = cache.list_for_root(self._root)
                self._emit_batches(records)
                self.completed.emit(len(records), 0, False)
                return

            references = self._selected_references or self._load_references()
            cookies = self._credentials.get_cookies()
            api = EhentaiApiClient(cookies=cookies)
            checker = GalleryPageStatusChecker(cookies=cookies)
            service = GalleryStatusService(api, checker, cache)
            pending_batch: list[GalleryStatusRecord] = []

            def handle_record(record: GalleryStatusRecord) -> None:
                pending_batch.append(record)
                if len(pending_batch) >= 100:
                    self.batch_ready.emit(list(pending_batch))
                    pending_batch.clear()

            summary = service.check(
                references,
                options=self._options,
                mode=self._mode,
                force_refresh=self._force_refresh,
                on_progress=self.progress.emit,
                on_record=handle_record,
                is_cancelled=self._cancel_event.is_set,
            )
            if pending_batch:
                self.batch_ready.emit(list(pending_batch))
            self.completed.emit(len(summary.records), summary.cache_hits, summary.cancelled)
        except (OSError, ValueError) as error:
            logger.exception("Gallery status check failed")
            self.failed.emit(str(error))
        except Exception as error:  # Worker boundary: preserve the remaining queue.
            logger.exception("Unexpected gallery status failure")
            self.failed.emit(f"画廊状态检查发生未预期错误：{error}")
        finally:
            if api is not None:
                api.close()
            if checker is not None:
                checker.close()
            self.finished.emit()

    def _load_references(self) -> list[GalleryReference]:
        galleries = self._database.list_galleries(self._root)
        parser = MetadataReferenceService()
        references: list[GalleryReference] = []
        total = len(galleries)
        for index, gallery in enumerate(galleries, start=1):
            if self._cancel_event.is_set():
                break
            parsed = parser.read_references(
                gallery.path,
                fallback_title=gallery.folder_name,
                fallback_size=gallery.folder_size,
            )
            if parsed:
                references.extend(parsed)
            else:
                expected_sources = parser.expected_sources(gallery.path)
                expected_label = " 或 ".join(expected_sources)
                references.append(
                    GalleryReference(
                        folder_path=gallery.path,
                        source="none",
                        gid=None,
                        token=None,
                        gallery_url=None,
                        local_title=gallery.folder_name,
                        local_filesize=gallery.folder_size,
                        parse_error=f"未找到该 ID 类型要求的 {expected_label}",
                    )
                )
            if index == total or index % 100 == 0:
                self.progress.emit(index, total, "正在读取本地 metadata")
        return references

    def _emit_batches(self, records: list[GalleryStatusRecord]) -> None:
        for start in range(0, len(records), 200):
            self.batch_ready.emit(records[start : start + 200])
