from __future__ import annotations

import threading
import time
from pathlib import Path

from app.models.gallery_folder import GalleryFolder, GalleryType, UnicodeStatus
from app.models.toolkit_features import ExistingCbzPolicy
from app.workers.feature_workers import FeatureWorker, pack_cbz


def test_pause_gate_blocks_until_resume() -> None:
    worker = FeatureWorker(lambda progress, cancelled: None)
    worker.request_pause()
    values: list[bool] = []
    thread = threading.Thread(target=lambda: values.append(worker._is_cancelled()))
    thread.start()
    time.sleep(0.02)
    assert thread.is_alive()
    worker.request_resume()
    thread.join(timeout=1)
    assert values == [False]


def test_cancel_releases_paused_worker() -> None:
    worker = FeatureWorker(lambda progress, cancelled: None)
    worker.request_pause()
    values: list[bool] = []
    thread = threading.Thread(target=lambda: values.append(worker._is_cancelled()))
    thread.start()
    worker.request_cancel()
    thread.join(timeout=1)
    assert values == [True]


def test_pack_queue_respects_test_limit(monkeypatch, tmp_path: Path) -> None:
    galleries = []
    for index in range(3):
        folder = tmp_path / f"{index} - Title"; folder.mkdir()
        galleries.append(GalleryFolder(str(index), GalleryType.NORMAL, folder.name, folder, UnicodeStatus.NFC, 0, 0, False, False, False, 1, "now"))

    class FakeDatabase:
        def list_galleries(self, root):
            return galleries

        def log_operation(self, *args):
            return None

        def prepare_cbz_tasks(self, galleries, output, policy):
            return None

        def update_cbz_task(self, source, target, status, policy, error=""):
            return None

    processed: list[Path] = []

    def fake_pack(self, seven_zip, gallery, destination, compression, policy, backup_root):
        processed.append(gallery.path)
        return "created", None

    monkeypatch.setattr("app.services.cbz_service.CbzService.pack_with_policy", fake_pack)
    action = pack_cbz(
        FakeDatabase(), tmp_path, tmp_path / "output", tmp_path / "7z.exe", 0,
        concurrency=2, policy=ExistingCbzPolicy.SKIP, limit=2,
    )
    result = action(lambda *_: None, lambda: False)
    assert len(processed) == 2
    assert result.success == 2 and result.skipped == 1
