from __future__ import annotations

from pathlib import Path
import shutil

from app.models.gallery_folder import GalleryFolder
from app.models.toolkit_features import PlanStatus, RenamePlan
from app.services.gallery_id_parser import parse_gallery_id


class NameOrganizerService:
    """Build and execute conservative Short -> Long rename plans."""

    def build_plans(self, galleries: list[GalleryFolder]) -> list[RenamePlan]:
        grouped: dict[tuple[str, str], list[GalleryFolder]] = {}
        for gallery in galleries:
            if gallery.gallery_id:
                grouped.setdefault((gallery.gallery_type.value, gallery.gallery_id), []).append(gallery)
        plans: list[RenamePlan] = []
        for (_, gallery_id), members in grouped.items():
            if len(members) < 2:
                continue
            longest = max(members, key=lambda item: len(item.folder_name))
            for member in members:
                if member is longest or len(member.folder_name) >= len(longest.folder_name):
                    continue
                target = member.path.with_name(longest.folder_name)
                status = PlanStatus.CONFLICT if target.exists() else PlanStatus.READY
                plans.append(RenamePlan(gallery_id, member.path, target, "同类型同 ID 使用最长名称", status))
        return sorted(plans, key=lambda item: (item.gallery_id, str(item.source)))

    def build_classification_plans(
        self,
        galleries: list[GalleryFolder],
        output_root: Path,
    ) -> list[RenamePlan]:
        """Plan duplicate moves into type/Short|Long without touching sources."""
        grouped: dict[tuple[str, str], list[GalleryFolder]] = {}
        for gallery in galleries:
            if gallery.gallery_id:
                grouped.setdefault((gallery.gallery_type.value, gallery.gallery_id), []).append(gallery)
        plans: list[RenamePlan] = []
        for (kind, gallery_id), members in grouped.items():
            if len(members) < 2:
                continue
            shortest = min(len(item.folder_name) for item in members)
            longest = max(len(item.folder_name) for item in members)
            for member in members:
                length = len(member.folder_name)
                role = "Short" if length == shortest and shortest != longest else "Long" if length == longest and shortest != longest else "Middle"
                target = output_root / f"{kind}_ID" / role / member.folder_name
                status = PlanStatus.CONFLICT if target.exists() else PlanStatus.READY
                plans.append(RenamePlan(gallery_id, member.path, target, f"重复 ID 分类为 {role}", status))
        return sorted(plans, key=lambda item: (item.gallery_id, item.reason, str(item.source)))

    def build_sync_plans(self, classification_root: Path) -> list[RenamePlan]:
        plans: list[RenamePlan] = []
        for kind in ("Normal_ID", "Archive_ID"):
            short_root = classification_root / kind / "Short"
            long_root = classification_root / kind / "Long"
            if not short_root.is_dir() or not long_root.is_dir():
                continue
            long_by_id: dict[str, Path] = {}
            for candidate in long_root.iterdir():
                parsed = parse_gallery_id(candidate.stem if candidate.suffix.casefold() == ".cbz" else candidate.name) if candidate.is_dir() or candidate.suffix.casefold() == ".cbz" else None
                if parsed:
                    current = long_by_id.get(parsed.gallery_id)
                    if current is None or len(candidate.name) > len(current.name):
                        long_by_id[parsed.gallery_id] = candidate
            for source in short_root.iterdir():
                parsed = parse_gallery_id(source.stem if source.suffix.casefold() == ".cbz" else source.name) if source.is_dir() or source.suffix.casefold() == ".cbz" else None
                if not parsed or parsed.gallery_id not in long_by_id:
                    continue
                target = source.with_name(long_by_id[parsed.gallery_id].name)
                if target == source:
                    continue
                status = PlanStatus.CONFLICT if target.exists() else PlanStatus.READY
                plans.append(RenamePlan(parsed.gallery_id, source, target, "使用 Long 名称同步 Short", status))
        return sorted(plans, key=lambda item: (item.gallery_id, str(item.source)))

    def execute(self, plan: RenamePlan) -> None:
        if plan.status is not PlanStatus.READY:
            raise FileExistsError(f"目标已存在：{plan.target}")
        if not plan.source.exists():
            raise FileNotFoundError(f"源项目不存在：{plan.source}")
        if plan.target.exists():
            raise FileExistsError(f"目标已存在：{plan.target}")
        try:
            plan.target.relative_to(plan.source)
        except ValueError:
            pass
        else:
            raise ValueError("目标目录不能位于源目录内部")
        plan.target.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(plan.source), str(plan.target))


def folder_title(folder_name: str) -> str:
    if folder_name.casefold().endswith(".cbz"):
        folder_name = folder_name[:-4]
    parts = folder_name.split(" - ", 2)
    if folder_name.startswith("Archive - ") and len(parts) == 3:
        return parts[2].strip()
    if len(parts) >= 2 and parts[0].strip().isdigit():
        return " - ".join(parts[1:]).strip()
    return folder_name.strip()
