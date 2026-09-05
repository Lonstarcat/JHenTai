from __future__ import annotations

import threading
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from PySide6.QtCore import QObject, Signal, Slot

from app.models.gallery_folder import GalleryFolder, GalleryStorage
from app.models.toolkit_features import CbzCheckResult, FeatureResult, RenamePlan
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

    def request_cancel(self) -> None:
        self._cancel.set()

    @Slot()
    def run(self) -> None:
        try:
            self.completed.emit(self._action(self.progress.emit, self._cancel.is_set))
        except Exception as error:
            self.failed.emit(str(error))
        finally:
            self.finished.emit()


def analyze_names(database: DatabaseService, root: Path, output_root: Path):
    return lambda progress, cancelled: NameOrganizerService().build_classification_plans(database.list_galleries(root), output_root)


def analyze_metadata(database: DatabaseService, root: Path):
    return lambda progress, cancelled: MetadataService().analyze(database.list_galleries(root))


def check_directories(database: DatabaseService, root: Path):
    return lambda progress, cancelled: DirectoryCheckService().check(database.list_galleries(root))


def compare_libraries(database: DatabaseService, root_a: Path, root_b: Path, cross_type: bool):
    def action(progress, cancelled):
        left = database.list_galleries(root_a)
        scanned = LibraryScannerService().scan(root_b, on_progress=progress, is_cancelled=cancelled)
        right = [item.gallery for item in scanned if item.gallery is not None]
        return LibraryCompareService().compare(left, right, cross_type)
    return action


def check_cbz(database: DatabaseService, root: Path, output: Path):
    def action(progress, cancelled):
        galleries = database.list_galleries(root)
        results: list[CbzCheckResult] = []
        service = CbzService()
        for index, gallery in enumerate(galleries, start=1):
            if cancelled():
                break
            target = gallery.path if gallery.storage_type is GalleryStorage.CBZ else output / f"{gallery.folder_name}.cbz"
            results.append(service.check(gallery, target))
            progress(index, len(galleries), gallery.folder_name)
        return results
    return action


def pack_cbz(database: DatabaseService, root: Path, output: Path, seven_zip: Path, compression: int, concurrency: int = 3):
    def action(progress, cancelled):
        result = FeatureResult()
        all_galleries = database.list_galleries(root)
        galleries = [gallery for gallery in all_galleries if gallery.storage_type is GalleryStorage.FOLDER]
        result.skipped += len(all_galleries) - len(galleries)
        service = CbzService()
        result_lock = threading.Lock()
        def process(gallery: GalleryFolder) -> None:
            target = output / f"{gallery.folder_name}.cbz"
            try:
                try:
                    target.relative_to(gallery.path)
                except ValueError:
                    pass
                else:
                    raise ValueError("CBZ 输出不能位于正在打包的漫画目录内部")
                if target.exists():
                    with result_lock: result.skipped += 1
                else:
                    service.pack(seven_zip, gallery.path, target, compression)
                    database.log_operation("CBZ 打包", "成功", gallery.path, target)
                    with result_lock: result.success += 1
            except Exception as error:
                database.log_operation("CBZ 打包", "失败", gallery.path, target, str(error))
                with result_lock: result.failed += 1
        with ThreadPoolExecutor(max_workers=min(8, max(1, concurrency))) as pool:
            futures = {pool.submit(process, gallery): gallery for gallery in galleries if not cancelled()}
            for index, future in enumerate(as_completed(futures), start=1):
                future.result()
                progress(index, len(futures), futures[future].folder_name)
                if cancelled():
                    for pending in futures: pending.cancel()
                    break
        return result
    return action
