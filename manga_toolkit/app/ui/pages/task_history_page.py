from __future__ import annotations

import csv
from pathlib import Path

from PySide6.QtWidgets import QFileDialog, QMessageBox, QPushButton

from app.services.database_service import DatabaseService
from app.ui.pages.feature_base_page import FeatureBasePage


class TaskHistoryPage(FeatureBasePage):
    def __init__(self, database: DatabaseService) -> None:
        super().__init__("任务记录", "查看所有写操作的时间、源/目标、结果和错误", (
            ("时间", lambda row: row.created_at.isoformat(sep=" ", timespec="seconds")), ("操作", lambda row: row.operation_type),
            ("结果", lambda row: row.result), ("源路径", lambda row: row.source_path), ("目标路径", lambda row: row.target_path),
            ("错误", lambda row: row.error),
        ), "刷新")
        self._database = database
        self.action_button.clicked.connect(self.refresh)
        export = QPushButton("导出 CSV"); export.clicked.connect(self.export_csv); self.header.add_action(export)
        self.refresh()
    def refresh(self) -> None:
        self.model.set_rows(self._database.list_operation_logs())
        self.task.status.setText(f"共 {len(self.model.rows)} 条操作记录")
    def export_csv(self) -> None:
        if not self.model.rows: QMessageBox.information(self, "任务记录", "没有可导出的记录。"); return
        value, _ = QFileDialog.getSaveFileName(self, "导出任务记录", "任务记录.csv", "CSV (*.csv)")
        if not value: return
        path = Path(value if value.casefold().endswith(".csv") else value + ".csv")
        try:
            with path.open("w", encoding="utf-8-sig", newline="") as stream:
                writer = csv.writer(stream); writer.writerow(("时间", "操作", "结果", "源路径", "目标路径", "错误"))
                for row in self.model.rows: writer.writerow((row.created_at.isoformat(), row.operation_type, row.result, row.source_path, row.target_path, row.error))
            QMessageBox.information(self, "导出完成", str(path))
        except OSError as error: QMessageBox.critical(self, "导出失败", str(error))
