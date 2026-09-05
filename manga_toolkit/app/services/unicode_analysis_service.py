from __future__ import annotations

import unicodedata
from collections import defaultdict
from collections.abc import Callable, Sequence

from app.models.gallery_folder import GalleryFolder
from app.models.library_analysis import UnicodeAnalysisResult, UnicodeDuplicateGroup

ProgressCallback = Callable[[int, int, str], None]
CancelCallback = Callable[[], bool]


class UnicodeAnalysisService:
    def analyze(
        self,
        galleries: Sequence[GalleryFolder],
        on_progress: ProgressCallback | None = None,
        is_cancelled: CancelCallback | None = None,
    ) -> UnicodeAnalysisResult:
        accepted: list[GalleryFolder] = []
        normalized: dict[str, list[GalleryFolder]] = defaultdict(list)
        total = len(galleries)
        for index, gallery in enumerate(galleries, start=1):
            if is_cancelled and is_cancelled():
                break
            accepted.append(gallery)
            normalized[unicodedata.normalize("NFC", gallery.folder_name)].append(gallery)
            if on_progress and (index == total or index % 500 == 0):
                on_progress(index, total, gallery.folder_name)

        duplicate_groups = [
            UnicodeDuplicateGroup(key, tuple(sorted(members, key=lambda item: item.folder_name)))
            for key, members in normalized.items()
            if len(members) > 1 and len({member.folder_name for member in members}) > 1
        ]
        duplicate_groups.sort(key=lambda group: group.normalized_name)
        return UnicodeAnalysisResult(accepted, duplicate_groups)
