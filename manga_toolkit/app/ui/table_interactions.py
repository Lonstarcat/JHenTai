from __future__ import annotations

import sys
from pathlib import Path

from PySide6.QtCore import QModelIndex, QPoint, QProcess, Qt, QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QAbstractItemView, QMenu, QTableView, QWidget


class TableInteractions:
    """Consistent column, sorting, and filesystem context menus for result tables."""

    def __init__(self, table: QTableView, filter_widget: QWidget | None = None) -> None:
        self.table = table
        table.setSortingEnabled(True)
        table.horizontalHeader().setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        table.horizontalHeader().customContextMenuRequested.connect(self._show_layout_menu)
        table.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        table.customContextMenuRequested.connect(self._show_row_menu)
        if filter_widget is not None:
            self.add_filter_widget(filter_widget)

    def add_filter_widget(self, widget: QWidget) -> None:
        widget.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        widget.customContextMenuRequested.connect(
            lambda point, source=widget: self._show_filter_menu(source, point)
        )

    def _show_filter_menu(self, widget: QWidget, point: QPoint) -> None:
        self._layout_menu().exec(widget.mapToGlobal(point))

    def _show_layout_menu(self, point: QPoint) -> None:
        header = self.table.horizontalHeader()
        self._layout_menu().exec(header.mapToGlobal(point))

    def _show_row_menu(self, point: QPoint) -> None:
        index = self.table.indexAt(point)
        menu = self._layout_menu()
        paths = self._paths_for_index(index)
        if paths:
            menu.addSeparator()
            for label, path in paths:
                action = menu.addAction(f"打开{label}")
                action.triggered.connect(lambda checked=False, value=path: self._open_path(value))
        menu.exec(self.table.viewport().mapToGlobal(point))

    def _layout_menu(self) -> QMenu:
        menu = QMenu(self.table)
        columns = menu.addMenu("显示 / 隐藏列")
        model = self.table.model()
        if model is not None:
            for column in range(model.columnCount()):
                title = str(model.headerData(column, Qt.Orientation.Horizontal) or f"第 {column + 1} 列")
                action = columns.addAction(title)
                action.setCheckable(True)
                action.setChecked(not self.table.isColumnHidden(column))
                action.toggled.connect(
                    lambda visible, index=column: self.table.setColumnHidden(index, not visible)
                )
            sorting = menu.addMenu("排序项目")
            for column in range(model.columnCount()):
                title = str(model.headerData(column, Qt.Orientation.Horizontal) or f"第 {column + 1} 列")
                column_menu = sorting.addMenu(title)
                ascending = column_menu.addAction("升序")
                descending = column_menu.addAction("降序")
                ascending.triggered.connect(
                    lambda checked=False, index=column: self.table.sortByColumn(index, Qt.SortOrder.AscendingOrder)
                )
                descending.triggered.connect(
                    lambda checked=False, index=column: self.table.sortByColumn(index, Qt.SortOrder.DescendingOrder)
                )
            sorting.addSeparator()
            clear_sort = sorting.addAction("恢复原始顺序")
            clear_sort.triggered.connect(lambda: self.table.sortByColumn(-1, Qt.SortOrder.AscendingOrder))
        return menu

    def _paths_for_index(self, index: QModelIndex) -> list[tuple[str, Path]]:
        if not index.isValid():
            return []
        model = self.table.model()
        source_index = index
        while model is not None and hasattr(model, "mapToSource") and hasattr(model, "sourceModel"):
            source_index = model.mapToSource(source_index)
            model = model.sourceModel()
        if model is None:
            return []
        record = None
        for accessor in ("row", "item_at", "record_at", "row_at", "gallery_at"):
            method = getattr(model, accessor, None)
            if method is None:
                continue
            try:
                record = method(source_index if accessor == "row" else source_index.row())
                break
            except (IndexError, TypeError):
                continue
        return self._extract_paths(record)

    @classmethod
    def _extract_paths(cls, record: object | None) -> list[tuple[str, Path]]:
        if record is None:
            return []
        nested = getattr(record, "gallery", None)
        if nested is not None:
            record = nested
        reference = getattr(record, "reference", None)
        candidates: list[tuple[str, object]] = []
        if reference is not None:
            candidates.append(("漫画位置", getattr(reference, "folder_path", None)))
        for label, attribute in (
            ("漫画位置", "path"),
            ("漫画文件夹", "folder"),
            ("源位置", "source"),
            ("源位置", "source_path"),
            ("CBZ 位置", "cbz_path"),
            ("库 A 位置", "path_a"),
            ("库 B 位置", "path_b"),
            ("目标位置", "target_path"),
            ("异常项位置", "item"),
        ):
            candidates.append((label, getattr(record, attribute, None)))
        result: list[tuple[str, Path]] = []
        seen: set[str] = set()
        for label, value in candidates:
            if value in (None, ""):
                continue
            path = Path(str(value))
            key = str(path).casefold()
            if key not in seen:
                seen.add(key)
                result.append((label, path))
        return result

    @staticmethod
    def _open_path(path: Path) -> None:
        if path.suffix.casefold() == ".cbz" or path.is_file():
            if sys.platform == "win32" and path.exists():
                QProcess.startDetached("explorer.exe", ["/select,", str(path)])
                return
            target = path.parent
        else:
            target = path
        if not target.exists():
            target = next((parent for parent in target.parents if parent.exists()), target.parent)
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(target)))


def install_table_interactions(table: QTableView, filter_widget: QWidget | None = None) -> None:
    existing = getattr(table, "_emangato_table_interactions", None)
    if isinstance(existing, TableInteractions):
        if filter_widget is not None:
            existing.add_filter_widget(filter_widget)
        return
    controller = TableInteractions(table, filter_widget)
    setattr(table, "_emangato_table_interactions", controller)
