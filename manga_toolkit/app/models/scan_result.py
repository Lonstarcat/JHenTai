from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from app.models.gallery_folder import GalleryFolder


@dataclass(frozen=True, slots=True)
class Issue:
    code: str
    message: str
    path: Path | None = None


@dataclass(frozen=True, slots=True)
class ScanResult:
    gallery: GalleryFolder | None = None
    issue: Issue | None = None


@dataclass(slots=True)
class ScanSummary:
    galleries: list[GalleryFolder] = field(default_factory=list)
    issues: list[Issue] = field(default_factory=list)
    cancelled: bool = False

    @property
    def total(self) -> int:
        return len(self.galleries)
