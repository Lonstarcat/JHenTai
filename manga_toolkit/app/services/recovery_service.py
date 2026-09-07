from __future__ import annotations

import shutil
from pathlib import Path

from app.models.toolkit_features import OperationLog


class RecoveryService:
    """Reverse only logged move/rename operations without overwriting data."""

    REVERSIBLE_OPERATIONS = {
        "名称同步",
        "名称分类移动",
        "Unicode 分类",
        "原地转换 NFC",
        "Excel 驱动移动 B",
        "CBZ 同名目录整理（移动）",
    }

    def can_restore(self, record: OperationLog) -> bool:
        return record.result == "成功" and record.operation_type in self.REVERSIBLE_OPERATIONS

    def restore(self, record: OperationLog) -> None:
        if not self.can_restore(record):
            raise ValueError("该记录不是可恢复的成功移动/改名操作")
        original = Path(record.source_path)
        current = Path(record.target_path)
        if original.exists():
            raise FileExistsError(f"原路径已存在，拒绝覆盖：{original}")
        if not current.exists():
            raise FileNotFoundError(f"当前路径不存在：{current}")
        try:
            original.relative_to(current)
        except ValueError:
            pass
        else:
            raise ValueError("恢复目标不能位于当前目录内部")
        original.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(current), str(original))
        if record.operation_type == "CBZ 同名目录整理（移动）":
            try:
                current.parent.rmdir()
            except OSError:
                pass
