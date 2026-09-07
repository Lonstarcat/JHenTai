from __future__ import annotations

import shutil
from pathlib import Path

from app.models.toolkit_features import CbzOrganizePlan, IsolationMode, PlanStatus


class CbzOrganizeService:
    """Plan and execute flat-CBZ to same-name-directory organization."""

    def build_plans(self, cbz_root: Path, mode: IsolationMode) -> list[CbzOrganizePlan]:
        if not cbz_root.is_dir():
            raise NotADirectoryError(cbz_root)
        plans: list[CbzOrganizePlan] = []
        for source in sorted(cbz_root.iterdir(), key=lambda path: path.name.casefold()):
            if not source.is_file() or source.suffix.casefold() != ".cbz":
                continue
            target = cbz_root / source.stem / source.name
            status = PlanStatus.CONFLICT if target.exists() or target.parent.is_file() else PlanStatus.READY
            plans.append(CbzOrganizePlan(source, target, mode, status))
        return plans

    def execute(self, plan: CbzOrganizePlan) -> None:
        if plan.status is not PlanStatus.READY:
            raise ValueError("CBZ 整理计划存在冲突")
        if not plan.source.is_file():
            raise FileNotFoundError(plan.source)
        if plan.target.exists() or plan.target.parent.is_file():
            raise FileExistsError(plan.target)
        plan.target.parent.mkdir(parents=False, exist_ok=True)
        if plan.mode is IsolationMode.COPY:
            shutil.copy2(plan.source, plan.target)
        else:
            shutil.move(str(plan.source), str(plan.target))
