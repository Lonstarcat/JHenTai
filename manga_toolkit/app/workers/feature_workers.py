from __future__ import annotations

import threading
import time
from collections.abc import Callable
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from pathlib import Path

from PySide6.QtCore import QObject, Signal, Slot

from app.models.gallery_folder import GalleryFolder, GalleryStorage
from app.models.toolkit_features import CbzCheckResult, CbzStatus, ExistingCbzPolicy, FeatureResult, RenamePlan
from app.services.cbz_service import CbzService
from app.services.database_service import DatabaseService
from app.services.directory_check_service import DirectoryCheckService
from app.services.library_compare_service import LibraryCompareService
from app.services.metadata_service import MetadataService
from app.services.name_organizer_service import NameOrganizerService
from app.services.scanner_service import LibraryScannerService


class FeatureWorker(QObject):
    progress = Signal(int, int, str)
    completed = Signal(object)
    failed = Signal(str)
    finished = Signal()

    def __init__(self, action: Callable[[Callable[[int, int, str], None], Callable[[], bool]], object]) -> None:
        super().__init__()
        self._action = action
        self._cancel = threading.Event()
        self._pause_gate = threading.Event()
        self._pause_gate.set()

    def request_cancel(self) -> None:
        self._cancel.set()
        self._pause_gate.set()

    def request_pause(self) -> None:
        self._pause_gate.clear()

    def request_resume(self) -> None:
        self._pause_gate.set()

    def _is_cancelled(self) -> bool:
        self._pause_gate.wait()
        return self._cancel.is_set()

    @Slot()
    def run(self) -> None:
        try:
            self.completed.emit(self._action(self.progress.emit, self._is_cancelled))
        except Exception as error:
            self.failed.emit(str(error))
        finally:
            self.finished.emit()


def analyze_names(database: DatabaseService, root: Path, output_root: Path):
    return lambda progress, cancelled: NameOrganizerService().build_classification_plans(database.list_galleries(root), output_root)


def analyze_metadata(database: DatabaseService, root: Path):
    def action(progress, cancelled):
        galleries = database.list_galleries(root)
        results = []
        service = MetadataService()
        for index, gallery in enumerate(galleries, 1):
            if cancelled():
                break
            results.extend(service.analyze([gallery]))
            progress(index, len(galleries), gallery.folder_name)
        return results
    return action


def check_directories(database: DatabaseService, root: Path):
    def action(progress, cancelled):
        galleries = database.list_galleries(root)
        results = []
        service = DirectoryCheckService()
        for index, gallery in enumerate(galleries, 1):
            if cancelled():
                break
            results.extend(service.check([gallery]))
            progress(index, len(galleries), gallery.folder_name)
        return results
    return action


def compare_libraries(database: DatabaseService, root_a: Path, root_b: Path, cross_type: bool):
    def action(progress, cancelled):
        left = database.list_galleries(root_a)
        scanned = LibraryScannerService().scan(root_b, on_progress=progress, is_cancelled=cancelled)
        right = [item.gallery for item in scanned if item.gallery is not None]
        return LibraryCompareService().compare(left, right, cross_type)
    return action


def check_cbz(database: DatabaseService, root: Path, output: Path):
    def action(progress, cancelled):
        galleries = [item for item in database.list_galleries(root) if item.storage_type is GalleryStorage.FOLDER]
        results: list[CbzCheckResult] = []
        service = CbzService()
        expected_names: set[str] = set()
        for index, gallery in enumerate(galleries, start=1):
            if cancelled():
                break
            target = output / f"{gallery.folder_name}.cbz"
            expected_names.add(target.name.casefold())
            results.append(service.check(gallery, target))
            progress(index, len(galleries), gallery.folder_name)
        if not cancelled() and output.is_dir():
            extras = [path for path in output.iterdir() if path.is_file() and path.suffix.casefold() == ".cbz" and path.name.casefold() not in expected_names]
            for path in extras:
                results.append(CbzCheckResult(root / path.stem, path, CbzStatus.EXTRA, 0, 0, "没有对应的已扫描原漫画目录"))
        return results
    return action


def pack_cbz(
    database: DatabaseService,
    root: Path,
    output: Path,
    seven_zip: Path,
    compression: int,
    concurrency: int = 3,
    policy: ExistingCbzPolicy = ExistingCbzPolicy.SKIP,
    limit: int | None = None,
):
    def action(progress, cancelled):
        result = FeatureResult()
        all_galleries = database.list_galleries(root)
        galleries = [gallery for gallery in all_galleries if gallery.storage_type is GalleryStorage.FOLDER]
        if limit is not None:
            galleries = galleries[: max(0, limit)]
        result.skipped += len(all_galleries) - len(galleries)
        service = CbzService()
        result_lock = threading.Lock()
        started = time.monotonic()
        backup_root = output / "cbz_backup"
        database.prepare_cbz_tasks(galleries, output, policy)
        def process(gallery: GalleryFolder) -> None:
            target = output / f"{gallery.folder_name}.cbz"
            try:
                database.update_cbz_task(gallery.path, target, "running", policy)
                try:
                    target.relative_to(gallery.path)
                except ValueError:
                    pass
                else:
                    raise ValueError("CBZ 输出不能位于正在打包的漫画目录内部")
                state, backup = service.pack_with_policy(seven_zip, gallery, target, compression, policy, backup_root)
                if state in {"skipped", "verified"}:
                    database.update_cbz_task(gallery.path, target, state, policy)
                    with result_lock: result.skipped += 1
                else:
                    detail = f"旧 CBZ 备份：{backup}" if backup else ""
                    database.log_operation("CBZ 打包", "成功", gallery.path, target, detail)
                    database.update_cbz_task(gallery.path, target, "completed", policy)
                    with result_lock: result.success += 1
            except Exception as error:
                database.log_operation("CBZ 打包", "失败", gallery.path, target, str(error))
                database.update_cbz_task(gallery.path, target, "failed", policy, str(error))
                with result_lock: result.failed += 1
        worker_count = min(8, max(1, concurrency))
        completed = 0
        iterator = iter(galleries)
        exhausted = False
        with ThreadPoolExecutor(max_workers=worker_count) as pool:
            futures = {}
            while futures or not exhausted:
                while len(futures) < worker_count and not exhausted:
                    if cancelled():
                        exhausted = True
                        result.cancelled = True
                        break
                    try:
                        gallery = next(iterator)
                    except StopIteration:
                        exhausted = True
                        break
                    futures[pool.submit(process, gallery)] = gallery
                if not futures:
                    break
                done, _ = wait(futures, return_when=FIRST_COMPLETED)
                for future in done:
                    gallery = futures.pop(future)
                    future.result()
                    completed += 1
                    elapsed = max(0.001, time.monotonic() - started)
                    progress(completed, len(galleries), f"{gallery.folder_name} · {completed / elapsed:.2f} 项/秒")
                if cancelled():
                    exhausted = True
                    result.cancelled = True
        return result
    return action
