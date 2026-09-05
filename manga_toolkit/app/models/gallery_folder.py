from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from app.models.gallery_status import GalleryStatus


class GalleryType(StrEnum):
    NORMAL = "Normal"
    ARCHIVE = "Archive"
    UNKNOWN = "Unknown"


class UnicodeStatus(StrEnum):
    NFC = "NFC"
    NFD = "NFD"
    OTHER = "OTHER"


class GalleryStorage(StrEnum):
    FOLDER = "Folder"
    CBZ = "CBZ"


@dataclass(frozen=True, slots=True)
class GalleryFolder:
    gallery_id: str | None
    gallery_type: GalleryType
    folder_name: str
    path: Path
    unicode_status: UnicodeStatus
    file_count: int
    folder_size: int
    has_metadata: bool
    has_ametadata: bool
    has_comic_info: bool
    modified_ns: int
    scanned_at: str
    from_cache: bool = False
    gid: int | None = None
    token: str | None = None
    gallery_url: str | None = None
    gallery_source: str | None = None
    remote_status: "GalleryStatus | None" = None
    current_gid: int | None = None
    current_token: str | None = None
    last_remote_check: datetime | None = None
    storage_type: GalleryStorage = GalleryStorage.FOLDER
