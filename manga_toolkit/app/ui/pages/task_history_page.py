from __future__ import annotations

import csv
from pathlib import Path

from PySide6.QtWidgets import QAbstractItemView, QFileDialog, QMessageBox, QPushButton, QTableView, QTabWidget

from app.services.database_service import DatabaseService
from app.services.recovery_service import RecoveryService
from app.models.toolkit_features import FeatureResult, OperationLog
from app.ui.pages.feature_base_page import FeatureBasePage
from app.ui.feature_table_model import FeatureTableModel
from app.ui.table_interactions import install_table_interactions


class TaskHistoryPage(FeatureBasePage):
    def __init__(self, database: DatabaseService) -> None:
        super().__init__("任务状态", "查看后台队列及所有写操作的时间、源/目标、结果和错误", (
            ("时间", lambda row: row.created_at.isoformat(sep=" ", timespec="seconds")), ("操作", lambda row: row.operation_type),
            ("结果", lambda row: row.result), ("源路径", lambda row: row.source_path), ("目标路径", lambda row: row.target_path),
            ("错误", lambda row: row.error),
        ), "刷新")
        self._database = database
        self.cbz_model = FeatureTableModel((
            ("更新时间", lambda row: row.updated_at.isoformat(sep=" ", timespec="seconds")),
            ("状态", lambda row: row.status),
            ("策略", lambda row: row.policy),
            ("源目录", lambda row: row.source_path),
            ("目标 CBZ", lambda row: row.target_path),
            ("错误", lambda row: row.error),
        ))
        self.layout.removeWidget(self.table)
        tabs = QTabWidget()
        tabs.addTab(self.table, "写操作日志")
        self.cbz_table = QTableView()
        self.cbz_table.setModel(self.cbz_model)
        self.cbz_table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.cbz_table.setAlternatingRowColors(True)
        self.cbz_table.setShowGrid(False)
        self.cbz_table.verticalHeader().setVisible(False)
        self.cbz_table.verticalHeader().setDefaultSectionSize(40)
        self.cbz_table.horizontalHeader().setStretchLastSection(True)
        install_table_interactions(self.cbz_table)
        tabs.addTab(self.cbz_table, "CBZ 队列状态")
        self.layout.addWidget(tabs, 1)
        self.action_button.clicked.connect(self.refresh)
        export = QPushButton("导出 CSV"); export.clicked.connect(self.export_csv); self.header.add_action(export)
        restore = QPushButton("恢复选中移动/改名"); restore.clicked.connect(self.restore_selected); self.header.add_action(restore)
        self.refresh()
    def refresh(self) -> None:
        self.model.set_rows(self._database.list_operation_logs())
        self.cbz_model.set_rows(self._database.list_cbz_tasks())
        self.task.status.setText(f"写操作 {len(self.model.rows)} 条 · CBZ 队列 {len(self.cbz_model.rows)} 条")
    def export_csv(self) -> None:
        if not self.model.rows: QMessageBox.information(self, "任务状态", "没有可导出的记录。"); return
        value, _ = QFileDialog.getSaveFileName(self, "导出任务状态", "任务状态.csv", "CSV (*.csv)")
        if not value: return
        path = Path(value if value.casefold().endswith(".csv") else value + ".csv")
        try:
            with path.open("w", encoding="utf-8-sig", newline="") as stream:
                writer = csv.writer(stream); writer.writerow(("时间", "操作", "结果", "源路径", "目标路径", "错误"))
                for row in self.model.rows: writer.writerow((row.created_at.isoformat(), row.operation_type, row.result, row.source_path, row.target_path, row.error))
            QMessageBox.information(self, "导出完成", str(path))
        except OSError as error: QMessageBox.critical(self, "导出失败", str(error))

    def restore_selected(self) -> None:
        selection = self.table.selectionModel().selectedRows() if self.table.selectionModel() else []
        service = RecoveryService()
        records = [
            row for index in selection
            if isinstance((row := self.model.row(index)), OperationLog) and service.can_restore(row)
        ]
        if not records:
            QMessageBox.information(self, "恢复操作", "请选择成功的名称移动、Unicode 分类、Excel 驱动移动或 CBZ 同名目录移动记录。")
            return
        if QMessageBox.question(self, "确认恢复", f"将反向移动 {len(records)} 个项目。原路径已存在时会拒绝覆盖，是否继续？") != QMessageBox.StandardButton.Yes:
            return

        def action(progress, cancelled):
            result = FeatureResult()
            for index, record in enumerate(records, 1):
                if cancelled(): break
                try:
                    service.restore(record)
                    self._database.log_operation(f"恢复：{record.operation_type}", "成功", record.target_path, record.source_path)
                    result.success += 1
                except Exception as error:
                    self._database.log_operation(f"恢复：{record.operation_type}", "失败", record.target_path, record.source_path, str(error))
                    result.failed += 1
                progress(index, len(records), Path(record.target_path).name)
            return result

        self.run_worker(action, "正在安全恢复移动/改名…", self._restore_completed, allow_pause=True)

    def _restore_completed(self, result: FeatureResult) -> None:
        self.task.status.setText(f"恢复完成 · 成功 {result.success} · 失败 {result.failed}")
        self.refresh()
        QMessageBox.information(self, "恢复操作", self.task.status.text() + "\n请重新扫描漫画库。")
