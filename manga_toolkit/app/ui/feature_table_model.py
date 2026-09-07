from __future__ import annotations

from collections.abc import Callable, Sequence

from PySide6.QtCore import QAbstractTableModel, QModelIndex, Qt


class FeatureTableModel(QAbstractTableModel):
    def __init__(self, columns: Sequence[tuple[str, Callable[[object], object]]]) -> None:
        super().__init__()
        self._columns = tuple(columns)
        self.rows: list[object] = []
        self._original_rows: list[object] = []

    def set_rows(self, rows: list[object]) -> None:
        self.beginResetModel()
        self._original_rows = list(rows)
        self.rows = list(rows)
        self.endResetModel()

    def sort(self, column: int, order: Qt.SortOrder = Qt.SortOrder.AscendingOrder) -> None:
        self.layoutAboutToBeChanged.emit()
        if column < 0:
            self.rows = list(self._original_rows)
        elif column < len(self._columns):
            getter = self._columns[column][1]
            self.rows.sort(
                key=lambda row: self._sort_key(getter(row)),
                reverse=order is Qt.SortOrder.DescendingOrder,
            )
        self.layoutChanged.emit()

    @staticmethod
    def _sort_key(value: object) -> tuple[int, object]:
        if value is None:
            return (2, "")
        if isinstance(value, (int, float)):
            return (0, value)
        return (1, str(value).casefold())

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self.rows)

    def columnCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self._columns)

    def data(self, index: QModelIndex, role: int = Qt.ItemDataRole.DisplayRole):
        if not index.isValid() or role not in (Qt.ItemDataRole.DisplayRole, Qt.ItemDataRole.ToolTipRole):
            return None
        value = self._columns[index.column()][1](self.rows[index.row()])
        return "" if value is None else str(value)

    def headerData(self, section: int, orientation: Qt.Orientation, role: int = Qt.ItemDataRole.DisplayRole):
        if role == Qt.ItemDataRole.DisplayRole and orientation == Qt.Orientation.Horizontal:
            return self._columns[section][0]
        return super().headerData(section, orientation, role)

    def row(self, index: QModelIndex) -> object | None:
        return self.rows[index.row()] if index.isValid() and index.row() < len(self.rows) else None

    @property
    def headers(self) -> list[str]:
        return [name for name, _ in self._columns]

    def values(self) -> list[list[object]]:
        return [[getter(row) for _, getter in self._columns] for row in self.rows]
