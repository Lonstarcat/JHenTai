from __future__ import annotations

from PySide6.QtCore import QAbstractTableModel, QModelIndex, QSortFilterProxyModel, Qt

from app.models.gallery_status import GalleryStatus, GalleryStatusRecord
from app.services.gallery_id_parser import parse_gallery_id


class GalleryStatusTableModel(QAbstractTableModel):
    HEADERS = (
        "状态",
        "本地ID",
        "来源",
        "本地标题",
        "本地GID",
        "最新GID",
        "页数变化",
        "本地页数",
        "最新页数",
        "本地大小",
        "最新大小",
        "最后检查时间",
        "备注",
    )

    def __init__(self) -> None:
        super().__init__()
        self._records: list[GalleryStatusRecord] = []

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self._records)

    def columnCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self.HEADERS)

    def data(
        self,
        index: QModelIndex,
        role: int = Qt.ItemDataRole.DisplayRole,
    ) -> object | None:
        if not index.isValid():
            return None
        record = self._records[index.row()]
        if role == Qt.ItemDataRole.ToolTipRole:
            return record.error or record.note or record.latest_url
        if role != Qt.ItemDataRole.DisplayRole:
            return None

        local_id = parse_gallery_id(record.reference.folder_path.name)
        local_count = record.local_metadata.filecount if record.local_metadata else record.reference.local_filecount
        local_size = record.local_metadata.filesize if record.local_metadata else record.reference.local_filesize
        current_count = record.current_metadata.filecount if record.current_metadata else None
        current_size = record.current_metadata.filesize if record.current_metadata else None
        values = (
            record.status.label,
            local_id.gallery_id if local_id else "—",
            record.reference.source,
            record.reference.local_title,
            record.local_gid or "—",
            record.current_gid or "—",
            f"{record.page_delta:+d}" if record.page_delta is not None else "—",
            local_count if local_count is not None else "—",
            current_count if current_count is not None else "—",
            self._format_size(local_size),
            self._format_size(current_size),
            record.checked_at.astimezone().strftime("%Y-%m-%d %H:%M:%S"),
            record.note or record.error,
        )
        return values[index.column()]

    def headerData(
        self,
        section: int,
        orientation: Qt.Orientation,
        role: int = Qt.ItemDataRole.DisplayRole,
    ) -> object | None:
        if role != Qt.ItemDataRole.DisplayRole:
            return None
        return self.HEADERS[section] if orientation == Qt.Orientation.Horizontal else str(section + 1)

    def clear(self) -> None:
        self.beginResetModel()
        self._records.clear()
        self.endResetModel()

    def append_batch(self, records: list[GalleryStatusRecord]) -> None:
        if not records:
            return
        first = len(self._records)
        self.beginInsertRows(QModelIndex(), first, first + len(records) - 1)
        self._records.extend(records)
        self.endInsertRows()

    def upsert_batch(self, records: list[GalleryStatusRecord]) -> None:
        existing = {
            self._record_key(record): index
            for index, record in enumerate(self._records)
        }
        additions: list[GalleryStatusRecord] = []
        changed_rows: list[int] = []
        for record in records:
            index = existing.get(self._record_key(record))
            if index is None:
                additions.append(record)
            else:
                self._records[index] = record
                changed_rows.append(index)
        for row in changed_rows:
            self.dataChanged.emit(
                self.index(row, 0),
                self.index(row, len(self.HEADERS) - 1),
            )
        self.append_batch(additions)

    def record_at(self, row: int) -> GalleryStatusRecord:
        return self._records[row]

    def records(self) -> list[GalleryStatusRecord]:
        return list(self._records)

    @staticmethod
    def _record_key(record: GalleryStatusRecord) -> tuple[str, str, int | None, str | None]:
        return (
            str(record.reference.folder_path),
            record.reference.source,
            record.reference.gid,
            record.reference.token,
        )

    @staticmethod
    def _format_size(value: int | None) -> str:
        if value is None:
            return "—"
        size = float(value)
        for unit in ("B", "KB", "MB", "GB", "TB"):
            if size < 1024 or unit == "TB":
                return f"{size:.1f} {unit}"
            size /= 1024
        return str(value)


class GalleryStatusFilterModel(QSortFilterProxyModel):
    def __init__(self) -> None:
        super().__init__()
        self._status: GalleryStatus | None = None
        self._search = ""

    def set_status_filter(self, status: GalleryStatus | None) -> None:
        self._status = status
        self.invalidateFilter()

    def set_search(self, value: str) -> None:
        self._search = value.casefold().strip()
        self.invalidateFilter()

    def filterAcceptsRow(self, source_row: int, source_parent: QModelIndex) -> bool:
        source = self.sourceModel()
        if not isinstance(source, GalleryStatusTableModel):
            return True
        record = source.record_at(source_row)
        if self._status is not None and record.status is not self._status:
            return False
        if not self._search:
            return True
        haystack = (
            f"{record.reference.local_title}\n{record.reference.folder_path}\n"
            f"{record.local_gid or ''}\n{record.current_gid or ''}\n{record.status.label}"
        ).casefold()
        return self._search in haystack
