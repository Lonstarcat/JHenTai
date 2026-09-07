from __future__ import annotations

from datetime import datetime
from pathlib import Path

import pytest

from app.models.toolkit_features import OperationLog
from app.services.recovery_service import RecoveryService


def record(source: Path, target: Path, operation: str = "名称分类移动") -> OperationLog:
    return OperationLog(1, datetime.now(), operation, str(source), str(target), "成功", "")


def test_restore_logged_move_without_overwrite(tmp_path: Path) -> None:
    source = tmp_path / "source" / "123 - Title"
    target = tmp_path / "processing" / "123 - Title"
    target.mkdir(parents=True)
    (target / "0.jpg").write_bytes(b"x")
    RecoveryService().restore(record(source, target))
    assert source.is_dir() and not target.exists()
    assert (source / "0.jpg").read_bytes() == b"x"


def test_restore_refuses_existing_original(tmp_path: Path) -> None:
    source = tmp_path / "source"; target = tmp_path / "target"
    source.mkdir(); target.mkdir()
    with pytest.raises(FileExistsError):
        RecoveryService().restore(record(source, target))


def test_only_known_successful_moves_are_reversible(tmp_path: Path) -> None:
    service = RecoveryService()
    assert not service.can_restore(record(tmp_path / "a", tmp_path / "b", "CBZ 打包"))
    assert service.can_restore(record(tmp_path / "a", tmp_path / "b", "Excel 驱动移动 B"))
    assert service.can_restore(record(tmp_path / "a.cbz", tmp_path / "a" / "a.cbz", "CBZ 同名目录整理（移动）"))


def test_restore_cbz_organizer_move_removes_empty_wrapper(tmp_path: Path) -> None:
    source = tmp_path / "A.cbz"
    target = tmp_path / "A" / "A.cbz"
    target.parent.mkdir()
    target.write_bytes(b"archive")
    RecoveryService().restore(record(source, target, "CBZ 同名目录整理（移动）"))
    assert source.read_bytes() == b"archive"
    assert not target.parent.exists()
