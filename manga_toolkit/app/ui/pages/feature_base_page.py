from __future__ import annotations

from collections.abc import Callable, Sequence

from PySide6.QtCore import QThread, Signal
from pathlib import Path

from PySide6.QtWidgets import QAbstractItemView, QFileDialog, QFrame, QHBoxLayout, QMessageBox, QPushButton, QTableView, QVBoxLayout, QWidget

from app.ui.components import PageHeader, TaskProgress
from app.ui.feature_table_model import FeatureTableModel
from app.workers.feature_workers import FeatureWorker
from app.services.report_service import ReportService
from app.ui.table_interactions import install_table_interactions


class FeatureBasePage(QWidget):
    task_state_changed = Signal(str)

    def __init__(self, title: str, subtitle: str, columns: Sequence[tuple[str, Callable[[object], object]]], action_text: str) -> None:
        super().__init__()
        self.setObjectName("PageRoot")
        self._thread: QThread | None = None
        self._worker: FeatureWorker | None = None
        self._paused = False
        self.model = FeatureTableModel(columns)
        self.layout = QVBoxLayout(self)
        self.layout.setContentsMargins(28, 26, 28, 26)
        self.layout.setSpacing(14)
        self.action_button = QPushButton(action_text)
        self.export_button = QPushButton("导出报告")
        self.export_button.clicked.connect(lambda: self.export_report(title))
        self._pause_task_button = QPushButton("暂停")
        self._pause_task_button.setEnabled(False)
        self._pause_task_button.clicked.connect(self.toggle_task_pause)
        self._cancel_task_button = QPushButton("取消")
        self._cancel_task_button.setEnabled(False)
        self._cancel_task_button.clicked.connect(self.cancel_running_task)
        self.header = PageHeader(title, subtitle)
        self.header.add_action(self.export_button)
        self.header.add_action(self._pause_task_button)
        self.header.add_action(self._cancel_task_button)
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
        install_table_interactions(self.table)
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
        install_table_interactions(self.table, panel)
        self.layout.insertWidget(1, panel)

    def export_report(self, title: str) -> None:
        if not self.model.rows:
            QMessageBox.information(self, "导出报告", "当前没有可导出的结果。")
            return
        value, selected_filter = QFileDialog.getSaveFileName(
            self,
            "导出报告",
            f"{title}.xlsx",
            "Excel (*.xlsx);;CSV (*.csv);;JSON (*.json)",
        )
        if not value:
            return
        suffix = Path(value).suffix.casefold()
        if suffix not in {".xlsx", ".csv", ".json"}:
            suffix = ".csv" if selected_filter.startswith("CSV") else ".json" if selected_filter.startswith("JSON") else ".xlsx"
            value += suffix
        destination = Path(value)
        headers = self.model.headers
        rows = self.model.values()
        service = ReportService()
        if suffix == ".csv":
            action = lambda progress, cancelled: service.export_table_csv(headers, rows, destination)
        elif suffix == ".json":
            action = lambda progress, cancelled: service.export_table_json(headers, rows, destination)
        else:
            action = lambda progress, cancelled: service.export_table(title, headers, rows, destination)
        self.run_worker(
            action,
            f"正在导出 {suffix[1:].upper()}…",
            lambda _: QMessageBox.information(self, "导出完成", str(destination)),
        )

    def export_excel(self, title: str) -> None:
        """Compatibility entry point retained for existing callers."""
        self.export_report(title)

    @property
    def is_running(self) -> bool:
        return self._thread is not None

    def stop(self) -> None:
        if self._worker is not None:
            self._worker.request_cancel()

    @property
    def is_paused(self) -> bool:
        return self._paused

    def pause(self) -> None:
        if self._worker is not None and not self._paused:
            self._worker.request_pause()
            self._paused = True

    def resume(self) -> None:
        if self._worker is not None and self._paused:
            self._worker.request_resume()
            self._paused = False

    def toggle_task_pause(self) -> None:
        if self._thread is None:
            return
        if self._paused:
            self.resume()
            self._pause_task_button.setText("暂停")
            self.task.status.setText("任务已继续")
        else:
            self.pause()
            self._pause_task_button.setText("继续")
            self.task.status.setText("任务将在当前安全检查点暂停")

    def cancel_running_task(self) -> None:
        if self._thread is None:
            return
        self.stop()
        self._cancel_task_button.setEnabled(False)
        self.task.status.setText("正在安全停止当前任务…")

    def run_worker(
        self,
        action,
        label: str,
        completed: Callable[[object], None] | None = None,
        *,
        allow_pause: bool = False,
    ) -> None:
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
        self._paused = False
        self.action_button.setEnabled(False)
        self._pause_task_button.setEnabled(allow_pause)
        self._cancel_task_button.setEnabled(True)
        self.task_state_changed.emit(label)
        self.task.begin(label)
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
        self._paused = False
        self.action_button.setEnabled(True)
        self._pause_task_button.setEnabled(False)
        self._pause_task_button.setText("暂停")
        self._cancel_task_button.setEnabled(False)
        self.task.finish()
        self.task_state_changed.emit("空闲")
