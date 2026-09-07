from __future__ import annotations

from app.models.gallery_folder import GalleryFolder
from app.models.toolkit_features import LibraryComparison


class LibraryCompareService:
    def compare(
        self,
        left: list[GalleryFolder],
        right: list[GalleryFolder],
        cross_type: bool = False,
        archive_threshold_bytes: int = 50 * 1024 * 1024,
    ) -> list[LibraryComparison]:
        def key(item: GalleryFolder) -> tuple[str, str]:
            return (("*" if cross_type else item.gallery_type.value), item.gallery_id or f"path:{item.folder_name}")
        left_map: dict[tuple[str, str], list[GalleryFolder]] = {}
        right_map: dict[tuple[str, str], list[GalleryFolder]] = {}
        for item in left: left_map.setdefault(key(item), []).append(item)
        for item in right: right_map.setdefault(key(item), []).append(item)
        results: list[LibraryComparison] = []
        for item_key in sorted(set(left_map) | set(right_map)):
            pending_a = list(left_map.get(item_key, [])); pending_b = list(right_map.get(item_key, []))
            for a in list(pending_a):
                match = next((b for b in pending_b if b.folder_name == a.folder_name), None)
                if match:
                    results.append(self._row(a, match, "相同", archive_threshold_bytes)); pending_a.remove(a); pending_b.remove(match)
            while pending_a and pending_b:
                results.append(self._row(pending_a.pop(0), pending_b.pop(0), "ID 相同名称不同", archive_threshold_bytes))
            results.extend(self._row(item, None, "仅 A 存在", archive_threshold_bytes) for item in pending_a)
            results.extend(self._row(None, item, "仅 B 存在", archive_threshold_bytes) for item in pending_b)
        return results

    @staticmethod
    def _row(
        a: GalleryFolder | None,
        b: GalleryFolder | None,
        status: str,
        archive_threshold_bytes: int,
    ) -> LibraryComparison:
        sample = a or b
        assert sample is not None
        recommendation = ""
        if a is not None and b is not None and a.gallery_type is not b.gallery_type:
            archive = a if a.gallery_type.value == "Archive" else b
            recommendation = (
                "建议保留 Archive"
                if archive.folder_size > archive_threshold_bytes
                else "建议保留 Normal"
            )
        return LibraryComparison(
            sample.gallery_id or "",
            sample.gallery_type.value,
            status,
            a.path if a else None,
            b.path if b else None,
            a.folder_name if a else "",
            b.folder_name if b else "",
            a.folder_size if a else 0,
            b.folder_size if b else 0,
            recommendation,
        )
