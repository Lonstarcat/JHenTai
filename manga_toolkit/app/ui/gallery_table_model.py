from __future__ import annotations

from PySide6.QtCore import QAbstractTableModel, QModelIndex, QSortFilterProxyModel, Qt

from app.models.gallery_folder import GalleryFolder


class GalleryTableModel(QAbstractTableModel):
    HEADERS = (
        "ID",
        "类型",
        "载体",
        "名称",
        "路径",
        "Unicode",
        "文件数",
        "大小",
        "metadata",
        "ametadata",
        "ComicInfo",
    )

    def __init__(self) -> None:
        super().__init__()
        self._items: list[GalleryFolder] = []

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self._items)

    def columnCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self.HEADERS)

    def data(
        self,
        index: QModelIndex,
        role: int = Qt.ItemDataRole.DisplayRole,
    ) -> object | None:
        if not index.isValid():
            return None
        gallery = self._items[index.row()]
        if role == Qt.ItemDataRole.ToolTipRole:
            return str(gallery.path)
        if role != Qt.ItemDataRole.DisplayRole:
            return None
        values = (
            gallery.gallery_id or "—",
            gallery.gallery_type.value,
            gallery.storage_type.value,
            gallery.folder_name,
            str(gallery.path),
            gallery.unicode_status.value,
            str(gallery.file_count),
            self._format_size(gallery.folder_size),
            "是" if gallery.has_metadata else "否",
            "是" if gallery.has_ametadata else "否",
            "是" if gallery.has_comic_info else "否",
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
        if orientation == Qt.Orientation.Horizontal:
            return self.HEADERS[section]
        return str(section + 1)

    def clear(self) -> None:
        self.beginResetModel()
        self._items.clear()
        self.endResetModel()

    def append_batch(self, items: list[GalleryFolder]) -> None:
        if not items:
            return
        first = len(self._items)
        last = first + len(items) - 1
        self.beginInsertRows(QModelIndex(), first, last)
        self._items.extend(items)
        self.endInsertRows()

    def item_at(self, row: int) -> GalleryFolder:
        return self._items[row]

    @staticmethod
    def _format_size(size: int) -> str:
        value = float(size)
        for unit in ("B", "KB", "MB", "GB", "TB"):
            if value < 1024 or unit == "TB":
                return f"{value:.1f} {unit}"
            value /= 1024
        return f"{size} B"


class GalleryFilterModel(QSortFilterProxyModel):
    def __init__(self) -> None:
        super().__init__()
        self._search = ""
        self._gallery_type = "全部类型"
        self._unicode = "全部编码"
        self._storage = "全部载体"

    def set_search(self, value: str) -> None:
        self._search = value.casefold().strip()
        self.invalidateFilter()

    def set_gallery_type(self, value: str) -> None:
        self._gallery_type = value
        self.invalidateFilter()

    def set_unicode(self, value: str) -> None:
        self._unicode = value
        self.invalidateFilter()

    def set_storage(self, value: str) -> None:
        self._storage = value
        self.invalidateFilter()

    def filterAcceptsRow(self, source_row: int, source_parent: QModelIndex) -> bool:
        source = self.sourceModel()
        if not isinstance(source, GalleryTableModel):
            return True
        gallery = source.item_at(source_row)
        if self._gallery_type != "全部类型" and gallery.gallery_type.value != self._gallery_type:
            return False
        if self._unicode != "全部编码" and gallery.unicode_status.value != self._unicode:
            return False
        if self._storage != "全部载体" and gallery.storage_type.value != self._storage:
            return False
        if not self._search:
            return True
        haystack = f"{gallery.gallery_id or ''}\n{gallery.folder_name}\n{gallery.path}".casefold()
        return self._search in haystack
