from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from app.models.gallery_folder import GalleryFolder


class DuplicateKind(StrEnum):
    NORMAL = "normal_normal"
    ARCHIVE = "archive_archive"
    CROSS_TYPE = "normal_archive"

    @property
    def label(self) -> str:
        return {
            DuplicateKind.NORMAL: "Normal ↔ Normal",
            DuplicateKind.ARCHIVE: "Archive ↔ Archive",
            DuplicateKind.CROSS_TYPE: "Normal ↔ Archive",
        }[self]


@dataclass(frozen=True, slots=True)
class DuplicateGroup:
    gallery_id: str
    kind: DuplicateKind
    members: tuple[GalleryFolder, ...]

    @property
    def shortest_length(self) -> int:
        return min(len(member.folder_name) for member in self.members)

    @property
    def longest_length(self) -> int:
        return max(len(member.folder_name) for member in self.members)

    def length_role(self, member: GalleryFolder) -> str:
        length = len(member.folder_name)
        if self.shortest_length == self.longest_length:
            return "同长度"
        if length == self.shortest_length:
            return "Short"
        if length == self.longest_length:
            return "Long"
        return "Middle"


@dataclass(frozen=True, slots=True)
class UnicodeDuplicateGroup:
    normalized_name: str
    members: tuple[GalleryFolder, ...]


@dataclass(slots=True)
class UnicodeAnalysisResult:
    galleries: list[GalleryFolder] = field(default_factory=list)
    duplicate_groups: list[UnicodeDuplicateGroup] = field(default_factory=list)

    @property
    def nfc_count(self) -> int:
        return sum(item.unicode_status.value == "NFC" for item in self.galleries)

    @property
    def nfd_count(self) -> int:
        return sum(item.unicode_status.value == "NFD" for item in self.galleries)

    @property
    def other_count(self) -> int:
        return sum(item.unicode_status.value == "OTHER" for item in self.galleries)
