from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum
from pathlib import Path


class PlanStatus(StrEnum):
    READY = "ready"
    CONFLICT = "conflict"
    SKIPPED = "skipped"


@dataclass(frozen=True, slots=True)
class RenamePlan:
    gallery_id: str
    source: Path
    target: Path
    reason: str
    status: PlanStatus = PlanStatus.READY


class UnicodeOperationType(StrEnum):
    COPY_NORMALIZED = "输出 NFC 副本"
    NORMALIZE_IN_PLACE = "原地转换 NFC"
    CLASSIFY = "Unicode 分类"
    MERGE = "NFC/NFD 合并"
    COPY_UNMATCHED = "复制未合并项"


@dataclass(frozen=True, slots=True)
class UnicodeOperationPlan:
    source: Path
    target: Path
    operation: UnicodeOperationType
    gallery_id: str | None = None
    companion: Path | None = None
    changes: tuple[str, ...] = ()
    status: PlanStatus = PlanStatus.READY
    reason: str = ""


@dataclass(frozen=True, slots=True)
class MetadataIssue:
    folder: Path
    file_name: str
    status: str
    title: str = ""
    folder_title: str = ""
    group_name: str = ""
    detail: str = ""


@dataclass(frozen=True, slots=True)
class DirectoryIssue:
    gallery_id: str | None
    folder: Path
    item: Path
    issue_type: str
    detail: str


@dataclass(frozen=True, slots=True)
class LibraryComparison:
    gallery_id: str
    gallery_type: str
    status: str
    path_a: Path | None
    path_b: Path | None
    name_a: str = ""
    name_b: str = ""
    size_a: int = 0
    size_b: int = 0
    recommendation: str = ""


@dataclass(frozen=True, slots=True)
class LibraryMatchPlan:
    gallery_id: str
    type_a: str
    type_b: str
    name_a: str
    name_b: str
    path_a: Path
    path_b: Path
    target_path: Path
    execute: bool = False
    status: PlanStatus = PlanStatus.READY
    note: str = ""


class CbzStatus(StrEnum):
    MISSING = "缺少 CBZ"
    VALID = "正常"
    DAMAGED = "损坏"
    EMPTY = "空包"
    NO_IMAGE = "缺少图片"
    NO_METADATA = "缺少 Metadata"
    NO_COMIC_INFO = "缺少 ComicInfo.xml"
    NESTED_ROOT = "存在多余顶层目录"
    COUNT_MISMATCH = "文件数量不一致"
    EXTRA = "多余 CBZ"


@dataclass(frozen=True, slots=True)
class CbzCheckResult:
    folder: Path
    cbz_path: Path
    status: CbzStatus
    source_count: int
    archive_count: int
    detail: str = ""


@dataclass(frozen=True, slots=True)
class CbzTaskRecord:
    source_path: str
    target_path: str
    status: str
    policy: str
    updated_at: datetime
    error: str = ""


class ExistingCbzPolicy(StrEnum):
    SKIP = "跳过"
    REBUILD = "重新生成"
    VERIFY = "验证后决定"


class IsolationMode(StrEnum):
    COPY = "复制"
    MOVE = "移动"


@dataclass(frozen=True, slots=True)
class IsolationPlan:
    source: Path
    target: Path
    item_type: str
    mode: IsolationMode
    status: PlanStatus = PlanStatus.READY
    reason: str = "缺少 ComicInfo.xml"


@dataclass(frozen=True, slots=True)
class CbzOrganizePlan:
    source: Path
    target: Path
    mode: IsolationMode
    status: PlanStatus = PlanStatus.READY
    reason: str = "按 CBZ 同名目录整理"


@dataclass(frozen=True, slots=True)
class OperationLog:
    id: int
    created_at: datetime
    operation_type: str
    source_path: str
    target_path: str
    result: str
    error: str


@dataclass(slots=True)
class FeatureResult:
    rows: list[object] = field(default_factory=list)
    success: int = 0
    failed: int = 0
    skipped: int = 0
    cancelled: bool = False
