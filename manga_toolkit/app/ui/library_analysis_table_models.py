from __future__ import annotations

import unicodedata
from dataclasses import dataclass

from PySide6.QtCore import QAbstractTableModel, QModelIndex, QSortFilterProxyModel, Qt

from app.models.gallery_folder import GalleryFolder
from app.models.library_analysis import DuplicateGroup, DuplicateKind, UnicodeDuplicateGroup


@dataclass(frozen=True, slots=True)
class DuplicateRow:
    group: DuplicateGroup
    gallery: GalleryFolder


class DuplicateTableModel(QAbstractTableModel):
    HEADERS = ("重复类型", "ID", "长短", "名称长度", "类型", "文件夹名", "大小", "Unicode", "路径")

    def __init__(self) -> None:
        super().__init__()
        self._rows: list[DuplicateRow] = []

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self._rows)

    def columnCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self.HEADERS)

    def data(self, index: QModelIndex, role: int = Qt.ItemDataRole.DisplayRole) -> object | None:
        if not index.isValid():
            return None
        row = self._rows[index.row()]
        if role == Qt.ItemDataRole.ToolTipRole:
            return str(row.gallery.path)
        if role != Qt.ItemDataRole.DisplayRole:
            return None
        values = (
            row.group.kind.label,
            row.group.gallery_id,
            row.group.length_role(row.gallery),
            len(row.gallery.folder_name),
            row.gallery.gallery_type.value,
            row.gallery.folder_name,
            self._format_size(row.gallery.folder_size),
            row.gallery.unicode_status.value,
            str(row.gallery.path),
        )
        return values[index.column()]

    def headerData(self, section: int, orientation: Qt.Orientation, role: int = Qt.ItemDataRole.DisplayRole) -> object | None:
        if role != Qt.ItemDataRole.DisplayRole:
            return None
        return self.HEADERS[section] if orientation == Qt.Orientation.Horizontal else str(section + 1)

    def set_groups(self, groups: list[DuplicateGroup]) -> None:
        self.beginResetModel()
        self._rows = [DuplicateRow(group, member) for group in groups for member in group.members]
        self.endResetModel()

    def row_at(self, row: int) -> DuplicateRow:
        return self._rows[row]

    @staticmethod
    def _format_size(value: int) -> str:
        size = float(value)
        for unit in ("B", "KB", "MB", "GB", "TB"):
            if size < 1024 or unit == "TB":
                return f"{size:.1f} {unit}"
            size /= 1024
        return str(value)


class DuplicateFilterModel(QSortFilterProxyModel):
    def __init__(self) -> None:
        super().__init__()
        self._search = ""
        self._kind: DuplicateKind | None = None

    def set_search(self, value: str) -> None:
        self._search = value.casefold().strip()
        self.invalidateFilter()

    def set_kind(self, kind: DuplicateKind | None) -> None:
        self._kind = kind
        self.invalidateFilter()

    def filterAcceptsRow(self, source_row: int, source_parent: QModelIndex) -> bool:
        source = self.sourceModel()
        if not isinstance(source, DuplicateTableModel):
            return True
        row = source.row_at(source_row)
        if self._kind is not None and row.group.kind is not self._kind:
            return False
        if not self._search:
            return True
        return self._search in (
            f"{row.group.gallery_id}\n{row.gallery.folder_name}\n{row.gallery.path}"
        ).casefold()


class UnicodeTableModel(QAbstractTableModel):
    HEADERS = ("Unicode", "ID", "类型", "文件夹名", "NFC 标准化名称", "路径")

    def __init__(self) -> None:
        super().__init__()
        self._galleries: list[GalleryFolder] = []

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self._galleries)

    def columnCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self.HEADERS)

    def data(self, index: QModelIndex, role: int = Qt.ItemDataRole.DisplayRole) -> object | None:
        if not index.isValid():
            return None
        gallery = self._galleries[index.row()]
        if role == Qt.ItemDataRole.ToolTipRole:
            return str(gallery.path)
        if role != Qt.ItemDataRole.DisplayRole:
            return None
        values = (
            gallery.unicode_status.value,
            gallery.gallery_id or "—",
            gallery.gallery_type.value,
            gallery.folder_name,
            unicodedata.normalize("NFC", gallery.folder_name),
            str(gallery.path),
        )
        return values[index.column()]

    def headerData(self, section: int, orientation: Qt.Orientation, role: int = Qt.ItemDataRole.DisplayRole) -> object | None:
        if role != Qt.ItemDataRole.DisplayRole:
            return None
        return self.HEADERS[section] if orientation == Qt.Orientation.Horizontal else str(section + 1)

    def set_galleries(self, galleries: list[GalleryFolder]) -> None:
        self.beginResetModel()
        self._galleries = list(galleries)
        self.endResetModel()

    def gallery_at(self, row: int) -> GalleryFolder:
        return self._galleries[row]


@dataclass(frozen=True, slots=True)
class UnicodeDuplicateRow:
    group: UnicodeDuplicateGroup
    gallery: GalleryFolder


class UnicodeDuplicateTableModel(QAbstractTableModel):
    HEADERS = ("状态", "ID", "类型", "Unicode", "原始文件夹名", "NFC 标准化名称", "路径")

    def __init__(self) -> None:
        super().__init__()
        self._rows: list[UnicodeDuplicateRow] = []

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self._rows)

    def columnCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self.HEADERS)

    def data(self, index: QModelIndex, role: int = Qt.ItemDataRole.DisplayRole) -> object | None:
        if not index.isValid():
            return None
        row = self._rows[index.row()]
        if role == Qt.ItemDataRole.ToolTipRole:
            return str(row.gallery.path)
        if role != Qt.ItemDataRole.DisplayRole:
            return None
        values = (
            "Unicode 重复",
            row.gallery.gallery_id or "—",
            row.gallery.gallery_type.value,
            row.gallery.unicode_status.value,
            row.gallery.folder_name,
            row.group.normalized_name,
            str(row.gallery.path),
        )
        return values[index.column()]

    def headerData(self, section: int, orientation: Qt.Orientation, role: int = Qt.ItemDataRole.DisplayRole) -> object | None:
        if role != Qt.ItemDataRole.DisplayRole:
            return None
        return self.HEADERS[section] if orientation == Qt.Orientation.Horizontal else str(section + 1)

    def set_groups(self, groups: list[UnicodeDuplicateGroup]) -> None:
        self.beginResetModel()
        self._rows = [UnicodeDuplicateRow(group, member) for group in groups for member in group.members]
        self.endResetModel()

    def row_at(self, row: int) -> UnicodeDuplicateRow:
        return self._rows[row]


class TextFilterModel(QSortFilterProxyModel):
    def __init__(self) -> None:
        super().__init__()
        self._search = ""
        self._status = "全部"

    def set_search(self, value: str) -> None:
        self._search = value.casefold().strip()
        self.invalidateFilter()

    def set_status(self, value: str) -> None:
        self._status = value
        self.invalidateFilter()

    def filterAcceptsRow(self, source_row: int, source_parent: QModelIndex) -> bool:
        model = self.sourceModel()
        if model is None:
            return True
        values = [str(model.index(source_row, column).data() or "") for column in range(model.columnCount())]
        if self._status != "全部" and self._status not in values:
            return False
        return not self._search or self._search in "\n".join(values).casefold()
