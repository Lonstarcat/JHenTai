from __future__ import annotations

import os
import codecs
import shutil
import tempfile
import unicodedata
from collections import defaultdict
from datetime import UTC, datetime
from pathlib import Path

from app.models.gallery_folder import GalleryFolder, GalleryStorage, GalleryType, UnicodeStatus
from app.models.toolkit_features import PlanStatus, UnicodeOperationPlan, UnicodeOperationType


class UnicodeOperationService:
    """Plan and execute conservative NFC operations without deleting source data."""

    TEXT_FILES = ("metadata", "ametadata", "ComicInfo.xml")
    IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif"}

    def build_normalization_plans(
        self,
        galleries: list[GalleryFolder],
        output_root: Path,
        *,
        in_place: bool = False,
    ) -> list[UnicodeOperationPlan]:
        plans: list[UnicodeOperationPlan] = []
        for gallery in galleries:
            if gallery.storage_type is not GalleryStorage.FOLDER or not gallery.path.is_dir():
                continue
            normalized_name = unicodedata.normalize("NFC", gallery.folder_name)
            changes: list[str] = []
            if normalized_name != gallery.folder_name:
                changes.append("文件夹名称")
            for file_name in self.TEXT_FILES:
                path = gallery.path / file_name
                if self._text_needs_normalization(path):
                    changes.append(file_name)
            if not changes:
                continue
            target = (
                gallery.path.with_name(normalized_name)
                if in_place
                else output_root / normalized_name
            )
            conflict = self._is_distinct_existing(gallery.path, target)
            plans.append(
                UnicodeOperationPlan(
                    source=gallery.path,
                    target=target,
                    operation=(
                        UnicodeOperationType.NORMALIZE_IN_PLACE
                        if in_place
                        else UnicodeOperationType.COPY_NORMALIZED
                    ),
                    gallery_id=gallery.gallery_id,
                    changes=tuple(changes),
                    status=PlanStatus.CONFLICT if conflict else PlanStatus.READY,
                    reason="仅执行 Unicode NFC 标准化",
                )
            )
        return sorted(plans, key=lambda item: (item.gallery_id or "", str(item.source)))

    def build_classification_plans(
        self,
        galleries: list[GalleryFolder],
        output_root: Path,
    ) -> list[UnicodeOperationPlan]:
        grouped: dict[tuple[str, str, str], list[GalleryFolder]] = defaultdict(list)
        for gallery in galleries:
            if (
                gallery.storage_type is GalleryStorage.FOLDER
                and gallery.gallery_type is GalleryType.ARCHIVE
                and gallery.gallery_id
            ):
                grouped[(gallery.gallery_type.value, gallery.gallery_id, unicodedata.normalize("NFC", gallery.folder_name))].append(gallery)
        plans: list[UnicodeOperationPlan] = []
        for members in grouped.values():
            original_names = {item.folder_name for item in members}
            if len(members) < 2 or len(original_names) < 2:
                continue
            if not ({item.unicode_status for item in members} & {UnicodeStatus.NFC}) or not (
                {item.unicode_status for item in members} & {UnicodeStatus.NFD}
            ):
                continue
            for gallery in members:
                target = output_root / "Unicode匹配" / gallery.unicode_status.value / gallery.folder_name
                plans.append(
                    UnicodeOperationPlan(
                        source=gallery.path,
                        target=target,
                        operation=UnicodeOperationType.CLASSIFY,
                        gallery_id=gallery.gallery_id,
                        changes=("移动目录",),
                        status=PlanStatus.CONFLICT if target.exists() else PlanStatus.READY,
                        reason="NFC 标准化后名称相同",
                    )
                )
        return sorted(plans, key=lambda item: (item.gallery_id or "", str(item.source)))

    def build_merge_plans(
        self,
        galleries: list[GalleryFolder],
        output_root: Path,
    ) -> list[UnicodeOperationPlan]:
        grouped: dict[tuple[str, str], list[GalleryFolder]] = defaultdict(list)
        for gallery in galleries:
            if gallery.gallery_id and gallery.storage_type is GalleryStorage.FOLDER:
                grouped[(gallery.gallery_type.value, gallery.gallery_id)].append(gallery)
        plans: list[UnicodeOperationPlan] = []
        for (_, gallery_id), members in grouped.items():
            nfc = [item for item in members if item.unicode_status is UnicodeStatus.NFC]
            nfd = [item for item in members if item.unicode_status is UnicodeStatus.NFD]
            pair_count = min(len(nfc), len(nfd))
            if pair_count == 0:
                continue
            for canonical, decomposed in zip(nfc[:pair_count], nfd[:pair_count]):
                target = output_root / "合并完成" / unicodedata.normalize("NFC", canonical.folder_name)
                plans.append(
                    UnicodeOperationPlan(
                        source=canonical.path,
                        companion=decomposed.path,
                        target=target,
                        operation=UnicodeOperationType.MERGE,
                        gallery_id=gallery_id,
                        changes=("合并文件", "文本 NFC 标准化"),
                        status=PlanStatus.CONFLICT if target.exists() else PlanStatus.READY,
                        reason="同类型同 ID 的 NFC/NFD 目录",
                    )
                )
            for unmatched in (*nfc[pair_count:], *nfd[pair_count:]):
                target = output_root / "未合并" / unmatched.unicode_status.value / unmatched.folder_name
                plans.append(
                    UnicodeOperationPlan(
                        source=unmatched.path,
                        target=target,
                        operation=UnicodeOperationType.COPY_UNMATCHED,
                        gallery_id=gallery_id,
                        changes=("复制目录",),
                        status=PlanStatus.CONFLICT if target.exists() else PlanStatus.READY,
                        reason="同 ID 组内没有可配对的另一编码目录",
                    )
                )
        return sorted(plans, key=lambda item: (item.gallery_id or "", str(item.source)))

    def execute(self, plan: UnicodeOperationPlan, backup_root: Path) -> list[Path]:
        if plan.status is not PlanStatus.READY:
            raise FileExistsError(f"计划不可执行：{plan.status.value}")
        if not plan.source.is_dir():
            raise FileNotFoundError(f"源目录不存在：{plan.source}")
        if plan.operation is UnicodeOperationType.COPY_NORMALIZED:
            self._copy_normalized(plan.source, plan.target)
            return []
        if plan.operation is UnicodeOperationType.NORMALIZE_IN_PLACE:
            return self._normalize_in_place(plan.source, plan.target, backup_root)
        if plan.operation is UnicodeOperationType.CLASSIFY:
            self._safe_move(plan.source, plan.target)
            return []
        if plan.operation is UnicodeOperationType.MERGE:
            if plan.companion is None or not plan.companion.is_dir():
                raise FileNotFoundError("NFD 配对目录不存在")
            self._merge(plan.source, plan.companion, plan.target)
            return []
        if plan.operation is UnicodeOperationType.COPY_UNMATCHED:
            self._copy_unchanged(plan.source, plan.target)
            return []
        raise ValueError(f"不支持的 Unicode 操作：{plan.operation}")

    def _copy_normalized(self, source: Path, target: Path) -> None:
        self._reject_nested_target(source, target)
        if target.exists():
            raise FileExistsError(f"目标已存在：{target}")
        target.parent.mkdir(parents=True, exist_ok=True)
        try:
            shutil.copytree(source, target, copy_function=shutil.copy2)
            self._normalize_known_texts(target)
        except Exception:
            if target.exists():
                shutil.rmtree(target)
            raise

    def _copy_unchanged(self, source: Path, target: Path) -> None:
        self._reject_nested_target(source, target)
        if target.exists():
            raise FileExistsError(f"目标已存在：{target}")
        target.parent.mkdir(parents=True, exist_ok=True)
        try:
            shutil.copytree(source, target, copy_function=shutil.copy2)
        except Exception:
            if target.exists():
                shutil.rmtree(target)
            raise

    def _normalize_in_place(self, source: Path, target: Path, backup_root: Path) -> list[Path]:
        if self._is_distinct_existing(source, target):
            raise FileExistsError(f"目标已存在：{target}")
        backups: list[tuple[Path, Path]] = []
        try:
            for file_name in self.TEXT_FILES:
                path = source / file_name
                if not self._text_needs_normalization(path):
                    continue
                backup = self._backup_file(path, backup_root / source.name)
                backups.append((path, backup))
                self._normalize_text(path)
            if target != source:
                source.rename(target)
            return [backup for _, backup in backups]
        except Exception:
            for original, backup in reversed(backups):
                if backup.is_file():
                    shutil.copy2(backup, original)
            raise

    def _merge(self, nfc_source: Path, nfd_source: Path, target: Path) -> None:
        self._reject_nested_target(nfc_source, target)
        self._reject_nested_target(nfd_source, target)
        if target.exists():
            raise FileExistsError(f"目标已存在：{target}")
        target.parent.mkdir(parents=True, exist_ok=True)
        candidates: dict[str, list[Path]] = defaultdict(list)
        for root in (nfc_source, nfd_source):
            for path in root.rglob("*"):
                if path.is_file():
                    relative = unicodedata.normalize("NFC", str(path.relative_to(root)).replace("\\", "/"))
                    candidates[relative].append(path)
        try:
            target.mkdir()
            for relative, sources in candidates.items():
                destination = target / Path(relative)
                destination.parent.mkdir(parents=True, exist_ok=True)
                selected = self._select_merge_source(relative, sources)
                shutil.copy2(selected, destination)
            self._normalize_known_texts(target)
        except Exception:
            if target.exists():
                shutil.rmtree(target)
            raise

    def _select_merge_source(self, relative: str, sources: list[Path]) -> Path:
        if len(sources) == 1:
            return sources[0]
        name = Path(relative).name.casefold()
        if Path(relative).suffix.casefold() in self.IMAGE_EXTENSIONS:
            return min(sources, key=lambda item: item.stat().st_mtime_ns)
        if name in {"metadata", "ametadata", "comicinfo.xml"}:
            return max(sources, key=lambda item: item.stat().st_mtime_ns)
        return max(sources, key=lambda item: item.stat().st_mtime_ns)

    @staticmethod
    def _safe_move(source: Path, target: Path) -> None:
        if target.exists():
            raise FileExistsError(f"目标已存在：{target}")
        try:
            target.relative_to(source)
        except ValueError:
            pass
        else:
            raise ValueError("目标目录不能位于源目录内部")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(source), str(target))

    def _normalize_known_texts(self, folder: Path) -> None:
        for file_name in self.TEXT_FILES:
            path = folder / file_name
            if self._text_needs_normalization(path):
                self._normalize_text(path)

    @staticmethod
    def _text_needs_normalization(path: Path) -> bool:
        if not path.is_file():
            return False
        try:
            text = path.read_bytes().decode("utf-8-sig")
        except (OSError, UnicodeError):
            return False
        return unicodedata.normalize("NFC", text) != text

    @staticmethod
    def _normalize_text(path: Path) -> None:
        stat = path.stat()
        original = path.read_bytes()
        has_bom = original.startswith(codecs.BOM_UTF8)
        text = original.decode("utf-8-sig")
        normalized = unicodedata.normalize("NFC", text)
        payload = normalized.encode("utf-8")
        if has_bom:
            payload = codecs.BOM_UTF8 + payload
        descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
        temporary = Path(temporary_name)
        try:
            with open(descriptor, "wb", closefd=True) as stream:
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
            temporary.replace(path)
            os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        except Exception:
            temporary.unlink(missing_ok=True)
            raise

    @staticmethod
    def _backup_file(source: Path, folder: Path) -> Path:
        folder.mkdir(parents=True, exist_ok=True)
        target = folder / source.name
        if target.exists():
            stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S%fZ")
            target = target.with_name(f"{source.name}.{stamp}.bak")
        shutil.copy2(source, target)
        return target

    @staticmethod
    def _is_distinct_existing(source: Path, target: Path) -> bool:
        if target == source or not target.exists():
            return False
        try:
            return not source.samefile(target)
        except OSError:
            return True

    @staticmethod
    def _reject_nested_target(source: Path, target: Path) -> None:
        try:
            target.relative_to(source)
        except ValueError:
            return
        raise ValueError("输出目录不能位于源漫画目录内部")
