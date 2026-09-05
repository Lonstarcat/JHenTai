from __future__ import annotations

import re
from dataclasses import dataclass

from app.models.gallery_folder import GalleryType


@dataclass(frozen=True, slots=True)
class ParsedGalleryId:
    gallery_type: GalleryType
    gallery_id: str


_ARCHIVE_PATTERN = re.compile(r"^Archive\s*-\s*(\d+)\s*-", re.IGNORECASE)
_NORMAL_PATTERN = re.compile(r"^(\d+)\s*-")


def parse_gallery_id(folder_name: str) -> ParsedGalleryId | None:
    """Parse a gallery identifier from a top-level folder name."""
    archive_match = _ARCHIVE_PATTERN.match(folder_name)
    if archive_match:
        return ParsedGalleryId(GalleryType.ARCHIVE, archive_match.group(1))

    normal_match = _NORMAL_PATTERN.match(folder_name)
    if normal_match:
        return ParsedGalleryId(GalleryType.NORMAL, normal_match.group(1))

    return None


def strip_gallery_prefix(folder_name: str) -> str:
    """Return the title portion without changing the original Unicode text."""
    archive_match = _ARCHIVE_PATTERN.match(folder_name)
    if archive_match:
        return folder_name[archive_match.end() :].lstrip()
    normal_match = _NORMAL_PATTERN.match(folder_name)
    if normal_match:
        return folder_name[normal_match.end() :].lstrip()
    return folder_name
