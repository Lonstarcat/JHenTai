from __future__ import annotations

import sqlite3
from collections.abc import Iterable
from datetime import datetime
from pathlib import Path

from app.models.gallery_folder import GalleryFolder, GalleryStorage, GalleryType, UnicodeStatus
from app.models.toolkit_features import OperationLog


class DatabaseService:
    def __init__(self, database_path: Path) -> None:
        self.database_path = database_path

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path, timeout=30)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA busy_timeout = 30000")
        return connection

    def initialize(self) -> None:
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.execute("PRAGMA journal_mode = WAL")
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS gallery_folders (
                    path TEXT PRIMARY KEY,
                    scan_root TEXT NOT NULL,
                    gallery_id TEXT,
                    gallery_type TEXT NOT NULL,
                    folder_name TEXT NOT NULL,
                    unicode_status TEXT NOT NULL,
                    file_count INTEGER NOT NULL,
                    folder_size INTEGER NOT NULL,
                    has_metadata INTEGER NOT NULL,
                    has_ametadata INTEGER NOT NULL,
                    has_comic_info INTEGER NOT NULL,
                    modified_ns INTEGER NOT NULL,
                    scanned_at TEXT NOT NULL,
                    scan_token TEXT NOT NULL,
                    storage_type TEXT NOT NULL DEFAULT 'Folder'
                );
                CREATE INDEX IF NOT EXISTS idx_gallery_root
                    ON gallery_folders(scan_root);
                CREATE INDEX IF NOT EXISTS idx_gallery_id_type
                    ON gallery_folders(gallery_id, gallery_type);

                CREATE TABLE IF NOT EXISTS operation_logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    operation_type TEXT NOT NULL,
                    source_path TEXT,
                    target_path TEXT,
                    result TEXT NOT NULL,
                    error TEXT
                );

                CREATE TABLE IF NOT EXISTS gallery_status_cache (
                    scan_root TEXT NOT NULL DEFAULT '',
                    folder_path TEXT NOT NULL,
                    source TEXT NOT NULL,
                    gid INTEGER NOT NULL,
                    token TEXT NOT NULL,
                    status TEXT NOT NULL,
                    local_title TEXT NOT NULL DEFAULT '',
                    gallery_url TEXT,
                    current_gid INTEGER,
                    current_token TEXT,
                    first_gid INTEGER,
                    parent_gid INTEGER,
                    replacement_gid INTEGER,
                    replacement_token TEXT,
                    latest_url TEXT,
                    replacement_url TEXT,
                    local_metadata_json TEXT,
                    current_metadata_json TEXT,
                    note TEXT NOT NULL DEFAULT '',
                    error TEXT NOT NULL DEFAULT '',
                    checked_at TEXT NOT NULL,
                    PRIMARY KEY (folder_path, source, gid, token)
                );
                CREATE INDEX IF NOT EXISTS idx_gallery_status_checked
                    ON gallery_status_cache(checked_at);
                CREATE INDEX IF NOT EXISTS idx_gallery_status_value
                    ON gallery_status_cache(status);
                """
            )
            self._ensure_gallery_columns(connection)
            self._ensure_status_cache_columns(connection)
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_gallery_status_root ON gallery_status_cache(scan_root)"
            )

    def load_cached(self, scan_root: Path) -> dict[str, GalleryFolder]:
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT * FROM gallery_folders WHERE scan_root = ?",
                (str(scan_root),),
            ).fetchall()
        return {row["path"]: self._row_to_gallery(row) for row in rows}

    def list_galleries(self, scan_root: Path) -> list[GalleryFolder]:
        return list(self.load_cached(scan_root).values())

    def log_operation(
        self,
        operation_type: str,
        result: str,
        source_path: Path | str | None = None,
        target_path: Path | str | None = None,
        error: str | None = None,
    ) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO operation_logs (
                    operation_type, source_path, target_path, result, error
                ) VALUES (?, ?, ?, ?, ?)
                """,
                (
                    operation_type,
                    str(source_path) if source_path else None,
                    str(target_path) if target_path else None,
                    result,
                    error,
                ),
            )

    def list_operation_logs(self, limit: int = 5000) -> list[OperationLog]:
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT * FROM operation_logs ORDER BY id DESC LIMIT ?",
                (max(1, limit),),
            ).fetchall()
        return [
            OperationLog(
                id=row["id"],
                created_at=datetime.fromisoformat(row["created_at"]),
                operation_type=row["operation_type"],
                source_path=row["source_path"] or "",
                target_path=row["target_path"] or "",
                result=row["result"],
                error=row["error"] or "",
            )
            for row in rows
        ]

    def replace_scan(
        self,
        scan_root: Path,
        galleries: Iterable[GalleryFolder],
        scan_token: str,
    ) -> None:
        rows = [
            (
                str(gallery.path),
                str(scan_root),
                gallery.gallery_id,
                gallery.gallery_type.value,
                gallery.folder_name,
                gallery.unicode_status.value,
                gallery.file_count,
                gallery.folder_size,
                int(gallery.has_metadata),
                int(gallery.has_ametadata),
                int(gallery.has_comic_info),
                gallery.modified_ns,
                gallery.scanned_at,
                scan_token,
                gallery.gid,
                gallery.token,
                gallery.gallery_url,
                gallery.gallery_source,
                gallery.storage_type.value,
            )
            for gallery in galleries
        ]
        with self._connect() as connection:
            connection.executemany(
                """
                INSERT INTO gallery_folders (
                    path, scan_root, gallery_id, gallery_type, folder_name,
                    unicode_status, file_count, folder_size, has_metadata,
                    has_ametadata, has_comic_info, modified_ns, scanned_at,
                    scan_token, gid, token, gallery_url, gallery_source, storage_type
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET
                    scan_root=excluded.scan_root,
                    gallery_id=excluded.gallery_id,
                    gallery_type=excluded.gallery_type,
                    folder_name=excluded.folder_name,
                    unicode_status=excluded.unicode_status,
                    file_count=excluded.file_count,
                    folder_size=excluded.folder_size,
                    has_metadata=excluded.has_metadata,
                    has_ametadata=excluded.has_ametadata,
                    has_comic_info=excluded.has_comic_info,
                    modified_ns=excluded.modified_ns,
                    scanned_at=excluded.scanned_at,
                    scan_token=excluded.scan_token,
                    gid=excluded.gid,
                    token=excluded.token,
                    gallery_url=excluded.gallery_url,
                    gallery_source=excluded.gallery_source,
                    storage_type=excluded.storage_type
                """,
                rows,
            )
            connection.execute(
                "DELETE FROM gallery_folders WHERE scan_root = ? AND scan_token <> ?",
                (str(scan_root), scan_token),
            )

    @staticmethod
    def _row_to_gallery(row: sqlite3.Row) -> GalleryFolder:
        return GalleryFolder(
            gallery_id=row["gallery_id"],
            gallery_type=GalleryType(row["gallery_type"]),
            folder_name=row["folder_name"],
            path=Path(row["path"]),
            unicode_status=UnicodeStatus(row["unicode_status"]),
            file_count=row["file_count"],
            folder_size=row["folder_size"],
            has_metadata=bool(row["has_metadata"]),
            has_ametadata=bool(row["has_ametadata"]),
            has_comic_info=bool(row["has_comic_info"]),
            modified_ns=row["modified_ns"],
            scanned_at=row["scanned_at"],
            from_cache=True,
            gid=row["gid"],
            token=row["token"],
            gallery_url=row["gallery_url"],
            gallery_source=row["gallery_source"],
            storage_type=GalleryStorage(row["storage_type"]),
        )

    @staticmethod
    def _ensure_gallery_columns(connection: sqlite3.Connection) -> None:
        columns = {
            row[1]
            for row in connection.execute("PRAGMA table_info(gallery_folders)").fetchall()
        }
        additions = {
            "gid": "INTEGER",
            "token": "TEXT",
            "gallery_url": "TEXT",
            "gallery_source": "TEXT",
            "storage_type": "TEXT NOT NULL DEFAULT 'Folder'",
        }
        for name, sql_type in additions.items():
            if name not in columns:
                connection.execute(
                    f"ALTER TABLE gallery_folders ADD COLUMN {name} {sql_type}"
                )

    @staticmethod
    def _ensure_status_cache_columns(connection: sqlite3.Connection) -> None:
        columns = {
            row[1]
            for row in connection.execute("PRAGMA table_info(gallery_status_cache)").fetchall()
        }
        if "scan_root" not in columns:
            connection.execute(
                "ALTER TABLE gallery_status_cache ADD COLUMN scan_root TEXT NOT NULL DEFAULT ''"
            )
