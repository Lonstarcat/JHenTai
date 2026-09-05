from __future__ import annotations

from collections.abc import Callable, Sequence

from PySide6.QtCore import QThread, Signal
from pathlib import Path

from PySide6.QtWidgets import QAbstractItemView, QFileDialog, QFrame, QHBoxLayout, QMessageBox, QPushButton, QTableView, QVBoxLayout, QWidget

from app.ui.components import PageHeader, TaskProgress
from app.ui.feature_table_model import FeatureTableModel
from app.workers.feature_workers import FeatureWorker
from app.services.report_service import ReportService


class FeatureBasePage(QWidget):
    task_state_changed = Signal(str)

    def __init__(self, title: str, subtitle: str, columns: Sequence[tuple[str, Callable[[object], object]]], action_text: str) -> None:
        super().__init__()
        self.setObjectName("PageRoot")
        self._thread: QThread | None = None
        self._worker: FeatureWorker | None = None
        self.model = FeatureTableModel(columns)
        self.layout = QVBoxLayout(self)
        self.layout.setContentsMargins(28, 26, 28, 26)
        self.layout.setSpacing(14)
        self.action_button = QPushButton(action_text)
        self.export_button = QPushButton("导出 Excel")
        self.export_button.clicked.connect(lambda: self.export_excel(title))
        self.header = PageHeader(title, subtitle)
        self.header.add_action(self.export_button)
        self.header.add_action(self.action_button, primary=True)
        self.layout.addWidget(self.header)
        self.task = TaskProgress(title, "等待操作；耗时任务将在后台运行")
        self.layout.addWidget(self.task)
        self.table = QTableView()
        self.table.setModel(self.model)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.ExtendedSelection)
        self.table.setAlternatingRowColors(True)
        self.table.setSortingEnabled(False)
        self.table.setShowGrid(False)
        self.table.verticalHeader().setVisible(False)
        self.table.verticalHeader().setDefaultSectionSize(40)
        self.table.horizontalHeader().setStretchLastSection(True)
        self.layout.addWidget(self.table, 1)

    def add_control_bar(self, *widgets: QWidget) -> None:
        panel = QFrame()
        panel.setObjectName("Panel")
        row = QHBoxLayout(panel)
        row.setContentsMargins(14, 10, 14, 10)
        row.setSpacing(8)
        for widget in widgets:
            row.addWidget(widget)
        row.addStretch(1)
        self.layout.insertWidget(1, panel)

    def export_excel(self, title: str) -> None:
        if not self.model.rows:
            QMessageBox.information(self, "导出报告", "当前没有可导出的结果。")
            return
        value, _ = QFileDialog.getSaveFileName(self, "导出报告", f"{title}.xlsx", "Excel (*.xlsx)")
        if not value:
            return
        destination = Path(value if value.casefold().endswith(".xlsx") else value + ".xlsx")
        headers = self.model.headers
        rows = self.model.values()
        self.run_worker(
            lambda progress, cancelled: ReportService().export_table(title, headers, rows, destination),
            "正在导出 Excel…",
            lambda _: QMessageBox.information(self, "导出完成", str(destination)),
        )

    @property
    def is_running(self) -> bool:
        return self._thread is not None

    def stop(self) -> None:
        if self._worker is not None:
            self._worker.request_cancel()

    def run_worker(self, action, label: str, completed: Callable[[object], None] | None = None) -> None:
        if self._thread is not None:
            return
        thread = QThread(self)
        worker = FeatureWorker(action)
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.progress.connect(lambda current, total, text: self.task.update_progress(current, total, f"{current} / {total} · {text}"))
        worker.completed.connect(completed or self._default_completed)
        worker.failed.connect(lambda message: QMessageBox.critical(self, "操作失败", message))
        worker.finished.connect(thread.quit)
        worker.finished.connect(worker.deleteLater)
        thread.finished.connect(self._thread_finished)
        thread.finished.connect(thread.deleteLater)
        self._thread = thread
        self._worker = worker
        self.action_button.setEnabled(False)
        self.task_state_changed.emit(label)
        self.task.update_progress(0, 1, label)
        thread.start()

    def _default_completed(self, result: object) -> None:
        if isinstance(result, list):
            self.model.set_rows(result)
            self.task.status.setText(f"完成 · {len(result)} 条结果")
        else:
            self.task.status.setText("操作完成")

    def _thread_finished(self) -> None:
        self._thread = None
        self._worker = None
        self.action_button.setEnabled(True)
        self.task_state_changed.emit("空闲")
