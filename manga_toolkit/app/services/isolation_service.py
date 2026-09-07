from __future__ import annotations

import shutil
from pathlib import Path

from app.models.toolkit_features import CbzCheckResult, CbzStatus, IsolationMode, IsolationPlan, PlanStatus


class IsolationService:
    """Build and execute non-overwriting ComicInfo isolation plans."""

    def build_plans(
        self,
        results: list[CbzCheckResult],
        folder_output: Path,
        cbz_output: Path,
        *,
        folder_mode: IsolationMode = IsolationMode.COPY,
        cbz_mode: IsolationMode = IsolationMode.COPY,
    ) -> list[IsolationPlan]:
        plans: list[IsolationPlan] = []
        seen: set[tuple[str, str]] = set()
        for result in results:
            if result.status is not CbzStatus.NO_COMIC_INFO:
                continue
            if result.folder.is_dir():
                target = folder_output / result.folder.name
                key = (str(result.folder), str(target))
                if key not in seen:
                    seen.add(key)
                    plans.append(self._plan(result.folder, target, "原漫画目录", folder_mode))
            if result.cbz_path.is_file():
                target = cbz_output / result.cbz_path.name
                key = (str(result.cbz_path), str(target))
                if key not in seen:
                    seen.add(key)
                    plans.append(self._plan(result.cbz_path, target, "CBZ", cbz_mode))
        return plans

    def execute(self, plan: IsolationPlan) -> None:
        if plan.status is not PlanStatus.READY:
            raise FileExistsError(f"隔离计划不可执行：{plan.status.value}")
        if not plan.source.exists():
            raise FileNotFoundError(f"源项目不存在：{plan.source}")
        if plan.target.exists():
            raise FileExistsError(f"目标已存在：{plan.target}")
        self._reject_nested(plan.source, plan.target)
        plan.target.parent.mkdir(parents=True, exist_ok=True)
        if plan.mode is IsolationMode.MOVE:
            shutil.move(str(plan.source), str(plan.target))
        elif plan.source.is_dir():
            try:
                shutil.copytree(plan.source, plan.target, copy_function=shutil.copy2)
            except Exception:
                if plan.target.exists():
                    shutil.rmtree(plan.target)
                raise
        else:
            try:
                shutil.copy2(plan.source, plan.target)
            except Exception:
                plan.target.unlink(missing_ok=True)
                raise

    @staticmethod
    def _plan(source: Path, target: Path, item_type: str, mode: IsolationMode) -> IsolationPlan:
        return IsolationPlan(
            source,
            target,
            item_type,
            mode,
            PlanStatus.CONFLICT if target.exists() else PlanStatus.READY,
        )

    @staticmethod
    def _reject_nested(source: Path, target: Path) -> None:
        if not source.is_dir():
            return
        try:
            target.relative_to(source)
        except ValueError:
            return
        raise ValueError("隔离目标不能位于源漫画目录内部")
