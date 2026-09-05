from __future__ import annotations

import unicodedata
from pathlib import Path

from PySide6.QtCore import QThread, Signal
from PySide6.QtWidgets import (
    QAbstractItemView,
    QComboBox,
    QFileDialog,
    QHBoxLayout,
    QMessageBox,
    QPushButton,
    QSplitter,
    QStackedWidget,
    QTabWidget,
    QTableView,
    QVBoxLayout,
    QWidget,
)

from app.models.library_analysis import UnicodeAnalysisResult
from app.services.database_service import DatabaseService
from app.services.settings_service import SettingsService
from app.ui.components import BadgeDelegate, DetailPanel, EmptyState, FilterBar, PageHeader, StatCard, TaskProgress
from app.ui.library_analysis_table_models import TextFilterModel, UnicodeDuplicateTableModel, UnicodeTableModel
from app.workers.analysis_report_worker import UnicodeReportWorker
from app.workers.library_analysis_worker import UnicodeAnalysisWorker


class UnicodeToolsPage(QWidget):
    task_state_changed = Signal(str)
    counts_changed = Signal(int)

    def __init__(self, database: DatabaseService, settings: SettingsService) -> None:
        super().__init__()
        self.setObjectName("PageRoot")
        self._database = database
        configured = settings.load().library_path
        self._root = Path(configured) if configured else None
        self._result: UnicodeAnalysisResult | None = None
        self._thread: QThread | None = None
        self._worker: UnicodeAnalysisWorker | None = None
        self._report_thread: QThread | None = None
        self._report_worker: UnicodeReportWorker | None = None
        self._detection_model = UnicodeTableModel()
        self._detection_proxy = TextFilterModel()
        self._detection_proxy.setSourceModel(self._detection_model)
        self._duplicate_model = UnicodeDuplicateTableModel()
        self._duplicate_proxy = TextFilterModel()
        self._duplicate_proxy.setSourceModel(self._duplicate_model)
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
        self.run_button = QPushButton("开始分析")
        self.run_button.clicked.connect(self.run_analysis)
        self.export_button = QPushButton("导出 Excel")
        self.export_button.clicked.connect(self.export_report)
        header = PageHeader("Unicode 工具", "检测 NFC/NFD 编码并识别规范化后名称相同的目录")
        header.add_action(self.export_button)
        header.add_action(self.run_button, primary=True)
        layout.addWidget(header)

        cards_row = QWidget()
        row = QHBoxLayout(cards_row)
        row.setContentsMargins(0, 0, 0, 0)
        self.nfc_card = StatCard("NFC")
        self.nfd_card = StatCard("NFD")
        self.other_card = StatCard("OTHER")
        self.duplicate_card = StatCard("Unicode 重复组")
        for card in (self.nfc_card, self.nfd_card, self.other_card, self.duplicate_card):
            row.addWidget(card)
        layout.addWidget(cards_row)
        self.task = TaskProgress("Unicode 分析", "等待分析；不会修改任何文件或名称")
        layout.addWidget(self.task)

        self.stack = QStackedWidget()
        empty = EmptyState("尚未分析 Unicode", "分析使用扫描缓存，不会遍历图片内容。", "开始分析")
        empty.action.clicked.connect(self.run_analysis)
        self.stack.addWidget(empty)
        tabs = QTabWidget()
        tabs.addTab(self._build_detection_tab(), "检测")
        tabs.addTab(self._build_duplicate_tab(), "重复")
        tabs.addTab(
            EmptyState("转换将在 Phase 3 开放", "转换前必须生成操作计划、预览并由用户确认。"),
            "转换",
        )
        self.stack.addWidget(tabs)
        layout.addWidget(self.stack, 1)

    def _build_detection_tab(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(0, 12, 0, 0)
        filters = FilterBar("搜索 ID、文件夹名或路径…")
        filters.search.textChanged.connect(self._detection_proxy.set_search)
        status = QComboBox()
        status.addItems(("全部", "NFC", "NFD", "OTHER"))
        status.currentTextChanged.connect(self._detection_proxy.set_status)
        filters.add_control(status)
        layout.addWidget(filters)
        splitter = QSplitter()
        self.detection_table = self._table(self._detection_proxy, {0, 2})
        self.detection_detail = DetailPanel()
        splitter.addWidget(self.detection_table)
        splitter.addWidget(self.detection_detail)
        splitter.setStretchFactor(0, 1)
        layout.addWidget(splitter, 1)
        selection = self.detection_table.selectionModel()
        if selection is not None:
            selection.currentRowChanged.connect(self._show_detection_detail)
        return page

    def _build_duplicate_tab(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(0, 12, 0, 0)
        filters = FilterBar("搜索原始名称、标准化名称或路径…")
        filters.search.textChanged.connect(self._duplicate_proxy.set_search)
        layout.addWidget(filters)
        splitter = QSplitter()
        self.duplicate_table = self._table(self._duplicate_proxy, {0, 2, 3})
        self.duplicate_detail = DetailPanel()
        splitter.addWidget(self.duplicate_table)
        splitter.addWidget(self.duplicate_detail)
        splitter.setStretchFactor(0, 1)
        layout.addWidget(splitter, 1)
        selection = self.duplicate_table.selectionModel()
        if selection is not None:
            selection.currentRowChanged.connect(self._show_duplicate_detail)
        return page

    @staticmethod
    def _table(model, badge_columns: set[int]) -> QTableView:
        table = QTableView()
        table.setModel(model)
        table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        table.setSortingEnabled(True)
        table.setAlternatingRowColors(True)
        table.setShowGrid(False)
        table.verticalHeader().setVisible(False)
        table.verticalHeader().setDefaultSectionSize(42)
        table.setItemDelegate(BadgeDelegate(badge_columns))
        table.setColumnWidth(0, 120)
        table.setColumnWidth(3, 360)
        return table

    def run_analysis(self) -> None:
        if self._thread is not None:
            return
        if self._root is None:
            QMessageBox.warning(self, "Unicode 工具", "请先完成漫画库扫描。")
            return
        thread = QThread(self)
        worker = UnicodeAnalysisWorker(self._database, self._root)
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
        self.task_state_changed.emit("正在分析 Unicode…")
        self.task.update_progress(0, 1, "正在读取扫描缓存…")
        thread.start()

    def stop(self) -> None:
        if self._worker is not None:
            self._worker.request_cancel()

    def export_report(self) -> None:
        if self._result is None:
            QMessageBox.information(self, "导出报告", "当前没有 Unicode 分析结果。")
            return
        destination, _ = QFileDialog.getSaveFileName(self, "导出 Unicode 报告", "Unicode分析报告.xlsx", "Excel (*.xlsx)")
        if not destination:
            return
        if not destination.casefold().endswith(".xlsx"):
            destination += ".xlsx"
        thread = QThread(self)
        worker = UnicodeReportWorker(self._result, Path(destination))
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

    def _on_completed(self, result: UnicodeAnalysisResult, cancelled: bool) -> None:
        self._result = result
        self._detection_model.set_galleries(result.galleries)
        self._duplicate_model.set_groups(result.duplicate_groups)
        self.nfc_card.set_value(result.nfc_count)
        self.nfd_card.set_value(result.nfd_count)
        self.other_card.set_value(result.other_count)
        self.duplicate_card.set_value(len(result.duplicate_groups))
        self.counts_changed.emit(result.nfd_count)
        self.stack.setCurrentIndex(1 if result.galleries else 0)
        state = "已取消" if cancelled else "分析完成"
        self.task.status.setText(f"{state} · {len(result.galleries)} 个目录")
        self.task.progress.setValue(self.task.progress.maximum())

    def _on_failed(self, message: str) -> None:
        self.task.status.setText("Unicode 分析失败")
        QMessageBox.critical(self, "Unicode 分析失败", message)

    def _thread_finished(self) -> None:
        self._thread = None
        self._worker = None
        self.run_button.setEnabled(True)
        self.task_state_changed.emit("空闲")

    def _report_finished(self) -> None:
        self._report_thread = None
        self._report_worker = None
        self.export_button.setEnabled(True)

    def _show_detection_detail(self, proxy_index, _previous) -> None:
        if not proxy_index.isValid():
            return
        gallery = self._detection_model.gallery_at(self._detection_proxy.mapToSource(proxy_index).row())
        self.detection_detail.set_details(
            gallery.folder_name,
            [
                ("ID", gallery.gallery_id or "—"),
                ("类型", gallery.gallery_type.value),
                ("Unicode", gallery.unicode_status.value),
                ("NFC 名称", unicodedata.normalize("NFC", gallery.folder_name)),
                ("NFD 名称", unicodedata.normalize("NFD", gallery.folder_name)),
                ("路径", str(gallery.path)),
            ],
        )

    def _show_duplicate_detail(self, proxy_index, _previous) -> None:
        if not proxy_index.isValid():
            return
        row = self._duplicate_model.row_at(self._duplicate_proxy.mapToSource(proxy_index).row())
        self.duplicate_detail.set_details(
            row.gallery.folder_name,
            [
                ("状态", "Unicode 编码重复"),
                ("组内数量", str(len(row.group.members))),
                ("Unicode", row.gallery.unicode_status.value),
                ("NFC 标准化名称", row.group.normalized_name),
                ("路径", str(row.gallery.path)),
            ],
        )
