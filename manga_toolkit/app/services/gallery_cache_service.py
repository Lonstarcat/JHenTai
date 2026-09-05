from __future__ import annotations

import json
import sqlite3
from dataclasses import asdict
from datetime import UTC, datetime, timedelta
from pathlib import Path

from app.models.gallery_status import (
    GalleryMetadataSnapshot,
    GalleryReference,
    GalleryStatus,
    GalleryStatusRecord,
)
from app.services.metadata_reference_service import MetadataReferenceService


class GalleryCacheService:
    def __init__(self, database_path: Path) -> None:
        self._database_path = database_path

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self._database_path, timeout=30)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout = 30000")
        return connection

    def get(self, reference: GalleryReference) -> GalleryStatusRecord | None:
        if reference.gid is None or not reference.token:
            return None
        if reference.source not in MetadataReferenceService.expected_sources(reference.folder_path):
            return None
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT * FROM gallery_status_cache
                WHERE folder_path = ? AND source = ? AND gid = ? AND token = ?
                """,
                (str(reference.folder_path), reference.source, reference.gid, reference.token),
            ).fetchone()
        if not row:
            return None
        try:
            return self._row_to_record(row)
        except (TypeError, ValueError, json.JSONDecodeError):
            # Treat an old or damaged cache row as a cache miss. A single bad
            # row must never abort a status run for the rest of the library.
            return None

    def is_fresh(self, record: GalleryStatusRecord, cache_hours: int) -> bool:
        return datetime.now(UTC) - record.checked_at <= timedelta(hours=cache_hours)

    def save(self, record: GalleryStatusRecord) -> None:
        reference = record.reference
        if reference.gid is None or not reference.token:
            return
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO gallery_status_cache (
                    scan_root, folder_path, source, gid, token, status, local_title,
                    gallery_url, current_gid, current_token, first_gid,
                    parent_gid, replacement_gid, replacement_token, latest_url,
                    replacement_url, local_metadata_json, current_metadata_json,
                    note, error, checked_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(folder_path, source, gid, token) DO UPDATE SET
                    status=excluded.status,
                    local_title=excluded.local_title,
                    gallery_url=excluded.gallery_url,
                    current_gid=excluded.current_gid,
                    current_token=excluded.current_token,
                    first_gid=excluded.first_gid,
                    parent_gid=excluded.parent_gid,
                    replacement_gid=excluded.replacement_gid,
                    replacement_token=excluded.replacement_token,
                    latest_url=excluded.latest_url,
                    replacement_url=excluded.replacement_url,
                    local_metadata_json=excluded.local_metadata_json,
                    current_metadata_json=excluded.current_metadata_json,
                    note=excluded.note,
                    error=excluded.error,
                    checked_at=excluded.checked_at
                """,
                (
                    str(reference.folder_path.parent),
                    str(reference.folder_path),
                    reference.source,
                    reference.gid,
                    reference.token,
                    record.status.value,
                    reference.local_title,
                    reference.gallery_url,
                    record.current_gid,
                    record.current_token,
                    record.first_gid,
                    record.parent_gid,
                    record.replacement_gid,
                    record.replacement_token,
                    record.latest_url,
                    record.replacement_url,
                    self._snapshot_json(record.local_metadata),
                    self._snapshot_json(record.current_metadata),
                    record.note,
                    record.error,
                    record.checked_at.isoformat(),
                ),
            )

    def list_for_root(self, root: Path) -> list[GalleryStatusRecord]:
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT * FROM gallery_status_cache WHERE scan_root = ? ORDER BY checked_at DESC",
                (str(root),),
            ).fetchall()
        records: list[GalleryStatusRecord] = []
        for row in rows:
            try:
                record = self._row_to_record(row)
                if record.reference.source not in MetadataReferenceService.expected_sources(
                    record.reference.folder_path
                ):
                    continue
                records.append(record)
            except (TypeError, ValueError, json.JSONDecodeError):
                continue
        return records

    @staticmethod
    def _snapshot_json(snapshot: GalleryMetadataSnapshot | None) -> str | None:
        return json.dumps(asdict(snapshot), ensure_ascii=False) if snapshot else None

    @staticmethod
    def _snapshot_from_json(value: str | None) -> GalleryMetadataSnapshot | None:
        if not value:
            return None
        data = json.loads(value)
        data["tags"] = tuple(data.get("tags", ()))
        return GalleryMetadataSnapshot(**data)

    @classmethod
    def _row_to_record(cls, row: sqlite3.Row) -> GalleryStatusRecord:
        local_metadata = cls._snapshot_from_json(row["local_metadata_json"])
        reference = GalleryReference(
            folder_path=Path(row["folder_path"]),
            source=row["source"],
            gid=row["gid"],
            token=row["token"],
            gallery_url=row["gallery_url"],
            local_title=row["local_title"],
            local_filecount=local_metadata.filecount if local_metadata else None,
            local_filesize=local_metadata.filesize if local_metadata else None,
        )
        return GalleryStatusRecord(
            reference=reference,
            status=GalleryStatus(row["status"]),
            checked_at=datetime.fromisoformat(row["checked_at"]),
            local_metadata=local_metadata,
            current_metadata=cls._snapshot_from_json(row["current_metadata_json"]),
            current_gid=row["current_gid"],
            current_token=row["current_token"],
            first_gid=row["first_gid"],
            parent_gid=row["parent_gid"],
            replacement_gid=row["replacement_gid"],
            replacement_token=row["replacement_token"],
            latest_url=row["latest_url"],
            replacement_url=row["replacement_url"],
            note=row["note"],
            error=row["error"],
            from_cache=True,
        )
