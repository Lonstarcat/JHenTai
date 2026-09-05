from __future__ import annotations

import json
import os
import re
import zipfile
from pathlib import Path
from typing import Any

from app.models.gallery_folder import GalleryType
from app.models.gallery_status import GalleryReference
from app.services.gallery_id_parser import parse_gallery_id


class MetadataReferenceService:
    MAX_METADATA_BYTES = 16 * 1024 * 1024
    _GALLERY_URL = re.compile(
        r"https?://(?:exhentai|e-hentai)\.org/g/(?P<gid>\d+)/(?P<token>[0-9a-fA-F]+)/?"
    )

    def read_references(
        self,
        folder_path: Path,
        fallback_title: str = "",
        fallback_size: int | None = None,
    ) -> list[GalleryReference]:
        sources = self.expected_sources(folder_path)
        if folder_path.is_file() and folder_path.suffix.casefold() == ".cbz":
            return self._archive_references(
                folder_path,
                fallback_title,
                fallback_size,
                sources,
            )
        files = self._metadata_files(folder_path)
        references: list[GalleryReference] = []
        for source in sources:
            file_path = files.get(source)
            if file_path is None:
                continue
            references.append(
                self._read_one(
                    file_path,
                    source,
                    fallback_title=fallback_title,
                    fallback_size=fallback_size,
                )
            )
        return references

    @staticmethod
    def expected_sources(container_path: Path) -> tuple[str, ...]:
        """Return metadata sources allowed by the gallery naming convention.

        Normal galleries use ``metadata`` and Archive galleries use
        ``ametadata``.  Unknown names retain the legacy fallback so files that
        cannot be classified from their name remain inspectable.
        """
        parsed = parse_gallery_id(container_path.name)
        if parsed is None:
            return ("metadata", "ametadata")
        if parsed.gallery_type is GalleryType.ARCHIVE:
            return ("ametadata",)
        return ("metadata",)

    def _archive_references(
        self,
        archive_path: Path,
        fallback_title: str,
        fallback_size: int | None,
        sources: tuple[str, ...],
    ) -> list[GalleryReference]:
        references: list[GalleryReference] = []
        try:
            with zipfile.ZipFile(archive_path) as archive:
                members = {
                    info.filename.replace("\\", "/").removeprefix("./").casefold(): info
                    for info in archive.infolist()
                    if not info.is_dir()
                    and "/" not in info.filename.replace("\\", "/").removeprefix("./")
                }
                for source in sources:
                    info = members.get(source)
                    if info is None:
                        continue
                    if info.file_size > self.MAX_METADATA_BYTES:
                        references.append(self._error_reference(archive_path, source, fallback_title, fallback_size, "metadata 文件异常过大"))
                        continue
                    try:
                        payload = archive.read(info).decode("utf-8-sig")
                        data = json.loads(payload)
                        if not isinstance(data, dict):
                            raise ValueError("metadata 顶层不是 JSON 对象")
                        references.append(self._from_data(data, archive_path, source, fallback_title, fallback_size))
                    except (UnicodeError, json.JSONDecodeError, ValueError, OSError, RuntimeError) as error:
                        references.append(self._error_reference(archive_path, source, fallback_title, fallback_size, str(error)))
        except (OSError, zipfile.BadZipFile, RuntimeError):
            return references
        return references

    def preferred_reference(
        self,
        folder_path: Path,
        fallback_title: str = "",
        fallback_size: int | None = None,
    ) -> GalleryReference | None:
        references = self.read_references(folder_path, fallback_title, fallback_size)
        valid = [reference for reference in references if reference.gid and reference.token]
        return valid[0] if valid else (references[0] if references else None)

    def _metadata_files(self, folder_path: Path) -> dict[str, Path]:
        result: dict[str, Path] = {}
        try:
            with os.scandir(folder_path) as entries:
                for entry in entries:
                    key = entry.name.casefold()
                    if key in {"metadata", "ametadata"} and entry.is_file(follow_symlinks=False):
                        result[key] = Path(entry.path)
        except OSError:
            return result
        return result

    def _read_one(
        self,
        file_path: Path,
        source: str,
        fallback_title: str,
        fallback_size: int | None,
    ) -> GalleryReference:
        try:
            if file_path.stat().st_size > self.MAX_METADATA_BYTES:
                raise ValueError("metadata 文件异常过大")
            data = json.loads(file_path.read_text(encoding="utf-8-sig"))
            if not isinstance(data, dict):
                raise ValueError("metadata 顶层不是 JSON 对象")
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
            return self._error_reference(file_path.parent, source, fallback_title, fallback_size, str(error))

        return self._from_data(data, file_path.parent, source, fallback_title, fallback_size)

    def _from_data(
        self,
        data: dict[str, Any],
        container_path: Path,
        source: str,
        fallback_title: str,
        fallback_size: int | None,
    ) -> GalleryReference:

        body: dict[str, Any]
        if source == "metadata" and isinstance(data.get("gallery"), dict):
            body = data["gallery"]
        else:
            body = data

        gid = self._to_int(body.get("gid"))
        token = self._to_text(body.get("token")) or None
        gallery_url = self._to_text(body.get("galleryUrl") or body.get("gallery_url")) or None
        if gallery_url:
            match = self._GALLERY_URL.match(gallery_url)
            if match:
                gid = gid or int(match.group("gid"))
                token = token or match.group("token")

        title = self._to_text(body.get("title")) or fallback_title
        filecount = self._to_int(body.get("filecount") or body.get("pageCount"))
        filesize = self._to_int(body.get("filesize")) or fallback_size
        parse_error = ""
        if gid is None:
            parse_error = "metadata 缺少 gid"
        elif not token:
            parse_error = "metadata 缺少 token"

        return GalleryReference(
            folder_path=container_path,
            source=source,
            gid=gid,
            token=token,
            gallery_url=gallery_url,
            local_title=title,
            local_filecount=filecount,
            local_filesize=filesize,
            parse_error=parse_error,
        )

    @staticmethod
    def _error_reference(
        container_path: Path,
        source: str,
        fallback_title: str,
        fallback_size: int | None,
        error: str,
    ) -> GalleryReference:
        return GalleryReference(
            folder_path=container_path,
            source=source,
            gid=None,
            token=None,
            gallery_url=None,
            local_title=fallback_title,
            local_filesize=fallback_size,
            parse_error=error,
        )

    @staticmethod
    def _to_int(value: object) -> int | None:
        try:
            return int(value) if value is not None and str(value).strip() else None
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _to_text(value: object) -> str:
        return str(value).strip() if value is not None else ""
