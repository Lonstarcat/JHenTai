from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum
from pathlib import Path


class GallerySite(StrEnum):
    EHENTAI = "e-hentai"
    EXHENTAI = "exhentai"

    @property
    def host(self) -> str:
        return "exhentai.org" if self is GallerySite.EXHENTAI else "e-hentai.org"


class GalleryStatus(StrEnum):
    LATEST = "latest"
    UPDATE_AVAILABLE = "update_available"
    OLDER_VERSION = "older_version"
    UNKNOWN_CHAIN = "unknown_chain"
    EXPUNGED = "expunged"
    REPLACED = "replaced"
    REMOVED = "removed"
    COPYRIGHT_REMOVED = "copyright_removed"
    DELETED = "deleted"
    PRIVATE = "private"
    TOKEN_INVALID = "token_invalid"
    ACCESS_DENIED = "access_denied"
    RATE_LIMITED = "rate_limited"
    NETWORK_ERROR = "network_error"
    UNKNOWN = "unknown"

    @property
    def label(self) -> str:
        return {
            GalleryStatus.LATEST: "当前最新",
            GalleryStatus.UPDATE_AVAILABLE: "存在新版本",
            GalleryStatus.OLDER_VERSION: "旧版本",
            GalleryStatus.UNKNOWN_CHAIN: "无法判断版本链",
            GalleryStatus.EXPUNGED: "已 Expunge",
            GalleryStatus.REPLACED: "已被其他画廊替换",
            GalleryStatus.REMOVED: "已移除 / 不可用",
            GalleryStatus.COPYRIGHT_REMOVED: "版权下架",
            GalleryStatus.DELETED: "已删除",
            GalleryStatus.PRIVATE: "私有画廊",
            GalleryStatus.TOKEN_INVALID: "Token 错误",
            GalleryStatus.ACCESS_DENIED: "访问被拒绝",
            GalleryStatus.RATE_LIMITED: "请求受限",
            GalleryStatus.NETWORK_ERROR: "网络错误",
            GalleryStatus.UNKNOWN: "未知",
        }[self]


ERROR_STATUSES = frozenset(
    {
        GalleryStatus.TOKEN_INVALID,
        GalleryStatus.ACCESS_DENIED,
        GalleryStatus.RATE_LIMITED,
        GalleryStatus.NETWORK_ERROR,
        GalleryStatus.UNKNOWN,
        GalleryStatus.UNKNOWN_CHAIN,
    }
)

UNAVAILABLE_STATUSES = frozenset(
    {
        GalleryStatus.EXPUNGED,
        GalleryStatus.REPLACED,
        GalleryStatus.REMOVED,
        GalleryStatus.COPYRIGHT_REMOVED,
        GalleryStatus.DELETED,
        GalleryStatus.PRIVATE,
    }
)


@dataclass(frozen=True, slots=True)
class GalleryReference:
    folder_path: Path
    source: str
    gid: int | None
    token: str | None
    gallery_url: str | None
    local_title: str
    local_filecount: int | None = None
    local_filesize: int | None = None
    parse_error: str = ""

    def build_url(self, site: GallerySite, gid: int | None = None, token: str | None = None) -> str | None:
        target_gid = gid if gid is not None else self.gid
        target_token = token if token is not None else self.token
        if target_gid is None or not target_token:
            return None
        return f"https://{site.host}/g/{target_gid}/{target_token}/"


@dataclass(frozen=True, slots=True)
class GalleryMetadataSnapshot:
    gid: int
    token: str
    title: str = ""
    title_jpn: str = ""
    filecount: int | None = None
    filesize: int | None = None
    posted: int | None = None
    category: str = ""
    tags: tuple[str, ...] = ()
    expunged: bool = False
    parent_gid: int | None = None
    parent_token: str | None = None
    current_gid: int | None = None
    current_token: str | None = None
    first_gid: int | None = None
    first_token: str | None = None
    error: str = ""


@dataclass(frozen=True, slots=True)
class GalleryStatusRecord:
    reference: GalleryReference
    status: GalleryStatus
    checked_at: datetime
    local_metadata: GalleryMetadataSnapshot | None = None
    current_metadata: GalleryMetadataSnapshot | None = None
    current_gid: int | None = None
    current_token: str | None = None
    first_gid: int | None = None
    parent_gid: int | None = None
    replacement_gid: int | None = None
    replacement_token: str | None = None
    latest_url: str | None = None
    replacement_url: str | None = None
    note: str = ""
    error: str = ""
    from_cache: bool = False

    @property
    def local_gid(self) -> int | None:
        return self.reference.gid

    @property
    def page_delta(self) -> int | None:
        old = self.local_metadata.filecount if self.local_metadata else self.reference.local_filecount
        new = self.current_metadata.filecount if self.current_metadata else None
        return None if old is None or new is None else new - old

    @property
    def size_delta(self) -> int | None:
        old = self.local_metadata.filesize if self.local_metadata else self.reference.local_filesize
        new = self.current_metadata.filesize if self.current_metadata else None
        return None if old is None or new is None else new - old


@dataclass(slots=True)
class GalleryStatusRunSummary:
    records: list[GalleryStatusRecord] = field(default_factory=list)
    skipped: int = 0
    cache_hits: int = 0
    cancelled: bool = False
