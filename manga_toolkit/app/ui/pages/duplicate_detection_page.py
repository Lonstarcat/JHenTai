from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QThread, Signal
from PySide6.QtWidgets import (
    QAbstractItemView,
    QCheckBox,
    QComboBox,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QMessageBox,
    QPushButton,
    QSplitter,
    QStackedWidget,
    QTableView,
    QVBoxLayout,
    QWidget,
)

from app.models.library_analysis import DuplicateGroup, DuplicateKind
from app.services.database_service import DatabaseService
from app.services.settings_service import SettingsService
from app.ui.components import BadgeDelegate, DetailPanel, EmptyState, FilterBar, PageHeader, StatCard, TaskProgress
from app.ui.library_analysis_table_models import DuplicateFilterModel, DuplicateTableModel
from app.ui.table_interactions import install_table_interactions
from app.workers.analysis_report_worker import DuplicateReportWorker
from app.workers.library_analysis_worker import DuplicateAnalysisWorker


class DuplicateDetectionPage(QWidget):
    task_state_changed = Signal(str)
    counts_changed = Signal(int)

    def __init__(self, database: DatabaseService, settings: SettingsService) -> None:
        super().__init__()
        self.setObjectName("PageRoot")
        self._database = database
        self._settings = settings
        configured = settings.load().library_path
        self._root = Path(configured) if configured else None
        self._groups: list[DuplicateGroup] = []
        self._thread: QThread | None = None
        self._worker: DuplicateAnalysisWorker | None = None
        self._report_thread: QThread | None = None
        self._report_worker: DuplicateReportWorker | None = None
        self._model = DuplicateTableModel()
        self._proxy = DuplicateFilterModel()
        self._proxy.setSourceModel(self._model)
        self._build_ui()

    @property
    def is_running(self) -> bool:
        return self._thread is not None or self._report_thread is not None

    def set_library_root(self, value: str) -> None:
        self._root = Path(value) if value else None

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(28, 26, 28, 26)
        layout.setSpacing(14)
        self.run_button = QPushButton("开始检测")
        self.run_button.clicked.connect(self.run_analysis)
        self.export_button = QPushButton("导出 Excel")
        self.export_button.clicked.connect(self.export_report)
        header = PageHeader("重复检测", "按集中解析的漫画 ID 检测同类型和跨类型重复目录")
        header.add_action(self.export_button)
        header.add_action(self.run_button, primary=True)
        layout.addWidget(header)

        mode_panel = QFrame()
        mode_panel.setObjectName("Panel")
        mode_layout = QHBoxLayout(mode_panel)
        mode_layout.setContentsMargins(14, 10, 14, 10)
        self.normal_normal = QCheckBox("Normal ↔ Normal")
        self.archive_archive = QCheckBox("Archive ↔ Archive")
        self.normal_archive = QCheckBox("Normal ↔ Archive")
        self.normal_normal.setChecked(True)
        self.archive_archive.setChecked(True)
        for item in (self.normal_normal, self.archive_archive, self.normal_archive):
            mode_layout.addWidget(item)
        mode_layout.addStretch(1)
        layout.addWidget(mode_panel)

        cards = QHBoxLayout()
        self.group_card = StatCard("重复组")
        self.item_card = StatCard("涉及目录")
        self.cross_card = StatCard("跨类型重复")
        cards.addWidget(self.group_card)
        cards.addWidget(self.item_card)
        cards.addWidget(self.cross_card)
        layout.addLayout(cards)

        filters = FilterBar("搜索 ID、文件夹名或路径…")
        filters.search.textChanged.connect(self._proxy.set_search)
        kind_combo = QComboBox()
        kind_combo.addItem("全部重复类型", None)
        for kind in DuplicateKind:
            kind_combo.addItem(kind.label, kind)
        kind_combo.currentIndexChanged.connect(
            lambda: self._proxy.set_kind(
                kind_combo.currentData() if isinstance(kind_combo.currentData(), DuplicateKind) else None
            )
        )
        filters.add_control(kind_combo)
        layout.addWidget(filters)

        self.task = TaskProgress("重复 ID 分析", "等待检测；本页面不会移动或删除目录")
        layout.addWidget(self.task)
        self.stack = QStackedWidget()
        empty = EmptyState("尚未检测重复 ID", "选择检测模式后开始分析已扫描的漫画库。", "开始检测")
        empty.action.clicked.connect(self.run_analysis)
        self.stack.addWidget(empty)
        splitter = QSplitter()
        self.table = QTableView()
        self.table.setModel(self._proxy)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.table.setSortingEnabled(True)
        self.table.setAlternatingRowColors(True)
        self.table.setShowGrid(False)
        self.table.verticalHeader().setVisible(False)
        self.table.verticalHeader().setDefaultSectionSize(42)
        self.table.setItemDelegate(BadgeDelegate({0, 2, 4, 7}))
        self.table.setColumnWidth(0, 160)
        self.table.setColumnWidth(1, 90)
        self.table.setColumnWidth(2, 90)
        self.table.setColumnWidth(5, 360)
        install_table_interactions(self.table, filters)
        self.detail = DetailPanel()
        splitter.addWidget(self.table)
        splitter.addWidget(self.detail)
        splitter.setStretchFactor(0, 1)
        self.stack.addWidget(splitter)
        layout.addWidget(self.stack, 1)
        selection = self.table.selectionModel()
        if selection is not None:
            selection.currentRowChanged.connect(self._show_detail)

    def run_analysis(self) -> None:
        if self._thread is not None:
            return
        if self._root is None:
            QMessageBox.warning(self, "重复检测", "请先完成漫画库扫描。")
            return
        if not any((self.normal_normal.isChecked(), self.archive_archive.isChecked(), self.normal_archive.isChecked())):
            QMessageBox.information(self, "重复检测", "请至少启用一种重复检测模式。")
            return
        thread = QThread(self)
        worker = DuplicateAnalysisWorker(
            self._database,
            self._root,
            self.normal_normal.isChecked(),
            self.archive_archive.isChecked(),
            self.normal_archive.isChecked(),
        )
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.progress.connect(self._on_progress)
        worker.completed.connect(self._on_completed)
        worker.failed.connect(self._on_failed)
        worker.finished.connect(thread.quit)
        worker.finished.connect(worker.deleteLater)
        thread.finished.connect(self._thread_finished)
        thread.finished.connect(thread.deleteLater)
        self._thread = thread
        self._worker = worker
        self.run_button.setEnabled(False)
        self.task_state_changed.emit("正在检测重复 ID…")
        self.task.update_progress(0, 1, "正在读取扫描缓存…")
        thread.start()

    def stop(self) -> None:
        if self._worker is not None:
            self._worker.request_cancel()

    def export_report(self) -> None:
        if not self._groups:
            QMessageBox.information(self, "导出报告", "当前没有重复检测结果。")
            return
        destination, _ = QFileDialog.getSaveFileName(self, "导出重复检测报告", "重复ID检测报告.xlsx", "Excel (*.xlsx)")
        if not destination:
            return
        if not destination.casefold().endswith(".xlsx"):
            destination += ".xlsx"
        thread = QThread(self)
        worker = DuplicateReportWorker(self._groups, Path(destination))
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.succeeded.connect(lambda path: QMessageBox.information(self, "导出完成", path))
        worker.failed.connect(lambda error: QMessageBox.critical(self, "导出失败", error))
        worker.finished.connect(thread.quit)
        worker.finished.connect(worker.deleteLater)
        thread.finished.connect(self._report_finished)
        thread.finished.connect(thread.deleteLater)
        self._report_thread = thread
        self._report_worker = worker
        self.export_button.setEnabled(False)
        thread.start()

    def _on_progress(self, current: int, total: int, text: str) -> None:
        self.task.update_progress(current, total, f"{current} / {total} · {text}")

    def _on_completed(self, groups: list[DuplicateGroup], cancelled: bool) -> None:
        self._groups = groups
        self._model.set_groups(groups)
        self.group_card.set_value(len(groups))
        self.item_card.set_value(sum(len(group.members) for group in groups))
        self.cross_card.set_value(sum(group.kind is DuplicateKind.CROSS_TYPE for group in groups))
        self.counts_changed.emit(len(groups))
        self.stack.setCurrentIndex(1 if groups else 0)
        state = "已取消" if cancelled else "分析完成"
        self.task.status.setText(f"{state} · {len(groups)} 个重复组")
        self.task.progress.setValue(self.task.progress.maximum())

    def _on_failed(self, message: str) -> None:
        self.task.status.setText("重复检测失败")
        QMessageBox.critical(self, "重复检测失败", message)

    def _thread_finished(self) -> None:
        self._thread = None
        self._worker = None
        self.run_button.setEnabled(True)
        self.task_state_changed.emit("空闲")

    def _report_finished(self) -> None:
        self._report_thread = None
        self._report_worker = None
        self.export_button.setEnabled(True)

    def _show_detail(self, proxy_index, _previous) -> None:
        if not proxy_index.isValid():
            return
        row = self._model.row_at(self._proxy.mapToSource(proxy_index).row())
        self.detail.set_details(
            row.gallery.folder_name,
            [
                ("ID", row.group.gallery_id),
                ("重复类型", row.group.kind.label),
                ("组内数量", str(len(row.group.members))),
                ("长短分类", row.group.length_role(row.gallery)),
                ("名称长度", str(len(row.gallery.folder_name))),
                ("目录类型", row.gallery.gallery_type.value),
                ("Unicode", row.gallery.unicode_status.value),
                ("路径", str(row.gallery.path)),
            ],
        )
