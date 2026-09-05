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


@dataclass(frozen=True, slots=True)
class CbzCheckResult:
    folder: Path
    cbz_path: Path
    status: CbzStatus
    source_count: int
    archive_count: int
    detail: str = ""


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
