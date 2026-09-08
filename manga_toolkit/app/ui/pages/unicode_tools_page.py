from __future__ import annotations

import unicodedata
from pathlib import Path

from PySide6.QtCore import QThread, Signal
from PySide6.QtWidgets import (
    QAbstractItemView,
    QComboBox,
    QFileDialog,
    QHBoxLayout,
    QLabel,
    QLineEdit,
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
from app.models.toolkit_features import FeatureResult, PlanStatus, UnicodeOperationPlan, UnicodeOperationType
from app.services.database_service import DatabaseService
from app.services.settings_service import SettingsService
from app.services.unicode_operation_service import UnicodeOperationService
from app.ui.components import BadgeDelegate, DetailPanel, EmptyState, FilterBar, PageHeader, StatCard, TaskProgress
from app.ui.library_analysis_table_models import TextFilterModel, UnicodeDuplicateTableModel, UnicodeTableModel
from app.ui.feature_table_model import FeatureTableModel
from app.ui.table_interactions import install_table_interactions
from app.workers.analysis_report_worker import UnicodeReportWorker
from app.workers.feature_workers import FeatureWorker
from app.workers.library_analysis_worker import UnicodeAnalysisWorker


class UnicodeToolsPage(QWidget):
    task_state_changed = Signal(str)
    counts_changed = Signal(int)

    def __init__(self, database: DatabaseService, settings: SettingsService) -> None:
        super().__init__()
        self.setObjectName("PageRoot")
        self._database = database
        self._settings = settings
        configured = settings.load().library_path
        self._root = Path(configured) if configured else None
        self._result: UnicodeAnalysisResult | None = None
        self._thread: QThread | None = None
        self._worker: UnicodeAnalysisWorker | None = None
        self._report_thread: QThread | None = None
        self._report_worker: UnicodeReportWorker | None = None
        self._operation_thread: QThread | None = None
        self._operation_worker: FeatureWorker | None = None
        self._detection_model = UnicodeTableModel()
        self._detection_proxy = TextFilterModel()
        self._detection_proxy.setSourceModel(self._detection_model)
        self._duplicate_model = UnicodeDuplicateTableModel()
        self._duplicate_proxy = TextFilterModel()
        self._duplicate_proxy.setSourceModel(self._duplicate_model)
        self._operation_model = FeatureTableModel((
            ("操作", lambda row: row.operation.value),
            ("状态", lambda row: row.status.value),
            ("ID", lambda row: row.gallery_id or "—"),
            ("源路径", lambda row: row.source),
            ("配对路径", lambda row: row.companion or ""),
            ("目标路径", lambda row: row.target),
            ("变更", lambda row: "、".join(row.changes)),
            ("说明", lambda row: row.reason),
        ))
        self._build_ui()

    @property
    def is_running(self) -> bool:
        return self._thread is not None or self._report_thread is not None or self._operation_thread is not None

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
        tabs.addTab(self._build_operation_tab(), "转换与合并")
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
        filters.bind_model(self._detection_proxy)
        layout.addWidget(filters)
        splitter = QSplitter()
        self.detection_table = self._table(self._detection_proxy, {0, 2})
        install_table_interactions(self.detection_table, filters)
        self.detection_detail = DetailPanel()
        splitter.addWidget(self.detection_table)
        splitter.addWidget(self.detection_detail)
        splitter.setStretchFactor(0, 1)
        layout.addWidget(splitter, 1)
        selection = self.detection_table.selectionModel()
        if selection is not None:
            selection.currentRowChanged.connect(self._show_detection_detail)
        return page

    def _build_operation_tab(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(0, 12, 0, 0)
        controls = QWidget()
        row = QHBoxLayout(controls)
        row.setContentsMargins(0, 0, 0, 0)
        self.operation_mode = QComboBox()
        self.operation_mode.addItem("输出 NFC 副本（推荐）", UnicodeOperationType.COPY_NORMALIZED.value)
        self.operation_mode.addItem("原地转换 NFC（高级模式）", UnicodeOperationType.NORMALIZE_IN_PLACE.value)
        self.operation_mode.addItem("NFC/NFD 分类移动", UnicodeOperationType.CLASSIFY.value)
        self.operation_mode.addItem("NFC/NFD 内容合并", UnicodeOperationType.MERGE.value)
        self.operation_output = QLineEdit()
        self.operation_output.setPlaceholderText("输出目录；默认位于漫画库同级")
        self.operation_output.setMinimumWidth(360)
        browse = QPushButton("选择输出目录")
        browse.clicked.connect(self._choose_operation_output)
        generate = QPushButton("生成操作计划")
        generate.clicked.connect(self.generate_operation_plans)
        self.execute_operations_button = QPushButton("执行计划")
        self.execute_operations_button.clicked.connect(self.execute_operation_plans)
        row.addWidget(QLabel("模式"))
        row.addWidget(self.operation_mode)
        row.addWidget(self.operation_output, 1)
        row.addWidget(browse)
        row.addWidget(generate)
        row.addWidget(self.execute_operations_button)
        layout.addWidget(controls)
        warning = QLabel("默认输出新目录且不修改源数据；原地转换会先备份 metadata、ametadata 和 ComicInfo.xml。所有操作均拒绝覆盖现有目标。")
        warning.setObjectName("SecondaryText")
        warning.setWordWrap(True)
        layout.addWidget(warning)
        table = QTableView()
        table.setModel(self._operation_model)
        table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        table.setSelectionMode(QAbstractItemView.SelectionMode.ExtendedSelection)
        table.setAlternatingRowColors(True)
        table.setShowGrid(False)
        table.verticalHeader().setVisible(False)
        table.verticalHeader().setDefaultSectionSize(40)
        table.horizontalHeader().setStretchLastSection(True)
        install_table_interactions(table)
        layout.addWidget(table, 1)
        return page

    def _build_duplicate_tab(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(0, 12, 0, 0)
        filters = FilterBar("搜索原始名称、标准化名称或路径…")
        filters.search.textChanged.connect(self._duplicate_proxy.set_search)
        filters.bind_model(self._duplicate_proxy)
        layout.addWidget(filters)
        splitter = QSplitter()
        self.duplicate_table = self._table(self._duplicate_proxy, {0, 2, 3})
        install_table_interactions(self.duplicate_table, filters)
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
        if self._thread is not None or self._operation_thread is not None:
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
        if self._operation_worker is not None:
            self._operation_worker.request_cancel()

    def _choose_operation_output(self) -> None:
        value = QFileDialog.getExistingDirectory(self, "选择 Unicode 操作输出目录")
        if value:
            self.operation_output.setText(value)

    def _operation_destination(self, operation: UnicodeOperationType) -> Path | None:
        if operation is UnicodeOperationType.NORMALIZE_IN_PLACE:
            return self._root
        configured = self.operation_output.text().strip()
        if configured:
            return Path(configured)
        if self._root is None:
            return None
        default_name = "Unicode_NFC" if operation is UnicodeOperationType.COPY_NORMALIZED else "Unicode处理"
        destination = self._root.parent / default_name
        self.operation_output.setText(str(destination))
        return destination

    def generate_operation_plans(self) -> None:
        if self._operation_thread is not None or self._thread is not None:
            return
        if self._root is None:
            QMessageBox.warning(self, "Unicode 工具", "请先完成漫画库扫描。")
            return
        operation = UnicodeOperationType(str(self.operation_mode.currentData()))
        if operation is UnicodeOperationType.NORMALIZE_IN_PLACE and self._settings.load().safety_mode:
            QMessageBox.warning(self, "安全模式", "原地 Unicode 转换只在高级模式下开放。请在设置中关闭安全模式，或使用“输出 NFC 副本”。")
            return
        destination = self._operation_destination(operation)
        if destination is None:
            QMessageBox.warning(self, "Unicode 工具", "请选择输出目录。")
            return

        def action(progress, cancelled):
            galleries = self._database.list_galleries(self._root)
            service = UnicodeOperationService()
            if operation in {UnicodeOperationType.COPY_NORMALIZED, UnicodeOperationType.NORMALIZE_IN_PLACE}:
                return service.build_normalization_plans(
                    galleries,
                    destination,
                    in_place=operation is UnicodeOperationType.NORMALIZE_IN_PLACE,
                )
            if operation is UnicodeOperationType.CLASSIFY:
                return service.build_classification_plans(galleries, destination)
            return service.build_merge_plans(galleries, destination)

        self._run_operation_worker(action, "正在生成 Unicode 操作计划…", self._plans_generated)

    def _plans_generated(self, plans: list[UnicodeOperationPlan]) -> None:
        self._operation_model.set_rows(plans)
        ready = sum(item.status is PlanStatus.READY for item in plans)
        conflicts = len(plans) - ready
        self.task.status.setText(f"计划生成完成 · 可执行 {ready} · 冲突 {conflicts}")

    def execute_operation_plans(self) -> None:
        plans = [
            item for item in self._operation_model.rows
            if isinstance(item, UnicodeOperationPlan) and item.status is PlanStatus.READY
        ]
        if not plans:
            QMessageBox.information(self, "Unicode 工具", "当前没有可执行计划。")
            return
        in_place = any(item.operation is UnicodeOperationType.NORMALIZE_IN_PLACE for item in plans)
        if in_place and self._settings.load().safety_mode:
            QMessageBox.warning(self, "安全模式", "原地转换计划不能在安全模式下执行。")
            return
        message = f"将执行 {len(plans)} 项计划。"
        if in_place:
            message += "\n其中包含原地修改；程序会先备份文本元数据，但文件夹名称变化需通过任务状态手动恢复。"
        else:
            message += "\n不会覆盖目标；输出副本和合并操作不会删除源目录。"
        if QMessageBox.question(self, "确认执行 Unicode 计划", message) != QMessageBox.StandardButton.Yes:
            return
        backup_root = (self._root or Path.cwd()) / "metadata_backup" / "unicode_nfc"

        def action(progress, cancelled):
            result = FeatureResult(); service = UnicodeOperationService()
            for index, plan in enumerate(plans, 1):
                if cancelled(): break
                try:
                    service.execute(plan, backup_root)
                    self._database.log_operation(plan.operation.value, "成功", plan.source, plan.target)
                    result.success += 1
                except Exception as error:
                    self._database.log_operation(plan.operation.value, "失败", plan.source, plan.target, str(error))
                    result.failed += 1
                progress(index, len(plans), plan.source.name)
            return result

        self._run_operation_worker(action, "正在执行 Unicode 计划…", self._operation_completed)

    def _run_operation_worker(self, action, label: str, completed) -> None:
        if self._operation_thread is not None:
            return
        thread = QThread(self)
        worker = FeatureWorker(action)
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.progress.connect(self._on_progress)
        worker.completed.connect(completed)
        worker.failed.connect(lambda message: QMessageBox.critical(self, "Unicode 操作失败", message))
        worker.finished.connect(thread.quit)
        worker.finished.connect(worker.deleteLater)
        thread.finished.connect(self._operation_finished)
        thread.finished.connect(thread.deleteLater)
        self._operation_thread = thread
        self._operation_worker = worker
        self.execute_operations_button.setEnabled(False)
        self.task_state_changed.emit(label)
        self.task.update_progress(0, 1, label)
        thread.start()

    def _operation_completed(self, result: FeatureResult) -> None:
        self.task.status.setText(f"完成 · 成功 {result.success} · 失败 {result.failed} · 跳过 {result.skipped}")
        QMessageBox.information(self, "Unicode 工具", self.task.status.text() + "\n执行后请重新扫描漫画库。")

    def _operation_finished(self) -> None:
        self._operation_thread = None
        self._operation_worker = None
        self.execute_operations_button.setEnabled(True)
        self.task_state_changed.emit("空闲")

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
