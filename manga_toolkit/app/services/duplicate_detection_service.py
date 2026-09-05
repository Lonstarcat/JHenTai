from __future__ import annotations

from collections import defaultdict
from collections.abc import Callable, Sequence

from app.models.gallery_folder import GalleryFolder, GalleryType
from app.models.library_analysis import DuplicateGroup, DuplicateKind

ProgressCallback = Callable[[int, int, str], None]
CancelCallback = Callable[[], bool]


class DuplicateDetectionService:
    def detect(
        self,
        galleries: Sequence[GalleryFolder],
        normal_normal: bool = True,
        archive_archive: bool = True,
        normal_archive: bool = False,
        on_progress: ProgressCallback | None = None,
        is_cancelled: CancelCallback | None = None,
    ) -> list[DuplicateGroup]:
        by_id: dict[str, dict[GalleryType, list[GalleryFolder]]] = defaultdict(
            lambda: defaultdict(list)
        )
        total = len(galleries)
        for index, gallery in enumerate(galleries, start=1):
            if is_cancelled and is_cancelled():
                break
            if gallery.gallery_id:
                by_id[gallery.gallery_id][gallery.gallery_type].append(gallery)
            if on_progress and (index == total or index % 500 == 0):
                on_progress(index, total, gallery.folder_name)

        groups: list[DuplicateGroup] = []
        for gallery_id, typed in by_id.items():
            normal = typed.get(GalleryType.NORMAL, [])
            archive = typed.get(GalleryType.ARCHIVE, [])
            if normal_normal and len(normal) > 1:
                groups.append(self._group(gallery_id, DuplicateKind.NORMAL, normal))
            if archive_archive and len(archive) > 1:
                groups.append(self._group(gallery_id, DuplicateKind.ARCHIVE, archive))
            if normal_archive and normal and archive:
                groups.append(
                    self._group(gallery_id, DuplicateKind.CROSS_TYPE, [*normal, *archive])
                )
        return sorted(groups, key=lambda group: (self._numeric_key(group.gallery_id), group.kind.value))

    @staticmethod
    def _group(
        gallery_id: str,
        kind: DuplicateKind,
        members: list[GalleryFolder],
    ) -> DuplicateGroup:
        return DuplicateGroup(
            gallery_id=gallery_id,
            kind=kind,
            members=tuple(sorted(members, key=lambda item: (len(item.folder_name), item.folder_name))),
        )

    @staticmethod
    def _numeric_key(value: str) -> tuple[int, str]:
        return (int(value), value) if value.isdigit() else (2**63 - 1, value)
