from __future__ import annotations

import logging
import os
import zipfile
from collections.abc import Callable
from dataclasses import replace
from datetime import UTC, datetime
from pathlib import Path

from app.models.gallery_folder import GalleryFolder, GalleryStorage, GalleryType
from app.models.scan_result import Issue, ScanResult
from app.services.gallery_id_parser import parse_gallery_id
from app.services.metadata_reference_service import MetadataReferenceService
from app.services.unicode_service import detect_unicode_status

logger = logging.getLogger(__name__)

ProgressCallback = Callable[[int, int, str], None]
CancelCallback = Callable[[], bool]
ResultCallback = Callable[[ScanResult], None]


class LibraryScannerService:
    """Read-only, one-level scanner designed for local disks and SMB shares."""

    IGNORED_DIRECTORIES = {"thumb", "metadata_backup"}

    def scan(
        self,
        root: Path,
        cached: dict[str, GalleryFolder] | None = None,
        on_progress: ProgressCallback | None = None,
        on_result: ResultCallback | None = None,
        is_cancelled: CancelCallback | None = None,
    ) -> list[ScanResult]:
        root = root.expanduser()
        cached = cached or {}
        if not root.exists():
            raise FileNotFoundError(f"漫画库不存在：{root}")
        if not root.is_dir():
            raise NotADirectoryError(f"漫画库不是目录：{root}")

        try:
            entries = [
                entry
                for entry in os.scandir(root)
                if (
                    entry.is_dir(follow_symlinks=False)
                    and entry.name.casefold() not in self.IGNORED_DIRECTORIES
                )
                or (
                    entry.is_file(follow_symlinks=False)
                    and Path(entry.name).suffix.casefold() == ".cbz"
                )
            ]
        except OSError as error:
            raise OSError(f"无法读取漫画库：{root}: {error}") from error

        total = len(entries)
        results: list[ScanResult] = []
        for index, entry in enumerate(entries, start=1):
            if is_cancelled and is_cancelled():
                break
            try:
                gallery = (
                    self._scan_folder(entry, cached)
                    if entry.is_dir(follow_symlinks=False)
                    else self._scan_cbz(entry, cached)
                )
                result = ScanResult(gallery=gallery)
            except OSError as error:
                path = Path(entry.path)
                logger.warning("Unable to scan %s: %s", path, error)
                cached_gallery = cached.get(str(path))
                result = ScanResult(
                    gallery=(
                        replace(
                            cached_gallery,
                            scanned_at=datetime.now(UTC).isoformat(),
                            from_cache=True,
                        )
                        if cached_gallery is not None
                        else None
                    ),
                    issue=Issue(
                        code="SCAN_IO_ERROR",
                        message=str(error),
                        path=path,
                    ),
                )
            results.append(result)
            if on_result:
                on_result(result)
            if on_progress and (index == total or index % 10 == 0):
                on_progress(index, total, entry.name)
        return results

    def _scan_cbz(
        self,
        entry: os.DirEntry[str],
        cached: dict[str, GalleryFolder],
    ) -> GalleryFolder:
        archive_path = Path(entry.path)
        archive_stat = entry.stat(follow_symlinks=False)
        cached_gallery = cached.get(str(archive_path))
        now = datetime.now(UTC).isoformat()
        if (
            cached_gallery is not None
            and cached_gallery.storage_type is GalleryStorage.CBZ
            and cached_gallery.modified_ns == archive_stat.st_mtime_ns
            and cached_gallery.folder_name == entry.name
        ):
            return replace(cached_gallery, scanned_at=now, from_cache=True)

        file_count = 0
        names: set[str] = set()
        try:
            with zipfile.ZipFile(archive_path) as archive:
                files = [info for info in archive.infolist() if not info.is_dir()]
                file_count = len(files)
                names = {
                    info.filename.replace("\\", "/").removeprefix("./").casefold()
                    for info in files
                    if "/" not in info.filename.replace("\\", "/").removeprefix("./")
                }
        except (OSError, zipfile.BadZipFile) as error:
            logger.warning("Unable to inspect CBZ %s: %s", archive_path, error)

        parsed_id = parse_gallery_id(archive_path.stem)
        reference = MetadataReferenceService().preferred_reference(
            archive_path,
            fallback_title=archive_path.stem,
            fallback_size=archive_stat.st_size,
        )
        return GalleryFolder(
            gallery_id=parsed_id.gallery_id if parsed_id else None,
            gallery_type=parsed_id.gallery_type if parsed_id else GalleryType.UNKNOWN,
            folder_name=entry.name,
            path=archive_path,
            unicode_status=detect_unicode_status(archive_path.stem),
            file_count=file_count,
            folder_size=archive_stat.st_size,
            has_metadata="metadata" in names,
            has_ametadata="ametadata" in names,
            has_comic_info="comicinfo.xml" in names,
            modified_ns=archive_stat.st_mtime_ns,
            scanned_at=now,
            from_cache=False,
            gid=reference.gid if reference else None,
            token=reference.token if reference else None,
            gallery_url=reference.gallery_url if reference else None,
            gallery_source=reference.source if reference else None,
            storage_type=GalleryStorage.CBZ,
        )

    def _scan_folder(
        self,
        entry: os.DirEntry[str],
        cached: dict[str, GalleryFolder],
    ) -> GalleryFolder:
        folder_path = Path(entry.path)
        folder_stat = entry.stat(follow_symlinks=False)
        cached_gallery = cached.get(str(folder_path))
        now = datetime.now(UTC).isoformat()
        if (
            cached_gallery is not None
            and cached_gallery.modified_ns == folder_stat.st_mtime_ns
            and cached_gallery.folder_name == entry.name
        ):
            return replace(cached_gallery, scanned_at=now, from_cache=True)

        file_count = 0
        folder_size = 0
        names: set[str] = set()
        with os.scandir(folder_path) as children:
            for child in children:
                names.add(child.name.casefold())
                if child.is_file(follow_symlinks=False):
                    file_count += 1
                    try:
                        folder_size += child.stat(follow_symlinks=False).st_size
                    except OSError as error:
                        logger.warning("Unable to stat %s: %s", child.path, error)

        parsed_id = parse_gallery_id(entry.name)
        reference = MetadataReferenceService().preferred_reference(
            folder_path,
            fallback_title=entry.name,
            fallback_size=folder_size,
        )
        return GalleryFolder(
            gallery_id=parsed_id.gallery_id if parsed_id else None,
            gallery_type=parsed_id.gallery_type if parsed_id else GalleryType.UNKNOWN,
            folder_name=entry.name,
            path=folder_path,
            unicode_status=detect_unicode_status(entry.name),
            file_count=file_count,
            folder_size=folder_size,
            has_metadata="metadata" in names,
            has_ametadata="ametadata" in names,
            has_comic_info="comicinfo.xml" in names,
            modified_ns=folder_stat.st_mtime_ns,
            scanned_at=now,
            from_cache=False,
            gid=reference.gid if reference else None,
            token=reference.token if reference else None,
            gallery_url=reference.gallery_url if reference else None,
            gallery_source=reference.source if reference else None,
            storage_type=GalleryStorage.FOLDER,
        )
