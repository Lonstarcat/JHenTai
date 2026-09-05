from __future__ import annotations

from pathlib import Path

from PySide6.QtWidgets import QComboBox, QMessageBox, QPushButton

from app.models.toolkit_features import FeatureResult, MetadataIssue
from app.services.database_service import DatabaseService
from app.services.metadata_service import MetadataService
from app.services.settings_service import SettingsService
from app.ui.pages.feature_base_page import FeatureBasePage
from app.workers.feature_workers import analyze_metadata


class MetadataPage(FeatureBasePage):
    def __init__(self, database: DatabaseService, settings: SettingsService) -> None:
        super().__init__("Metadata", "检查 metadata/ametadata、标题差异，并在备份后修改选中项 groupName", (
            ("文件夹", lambda row: row.folder), ("文件", lambda row: row.file_name), ("状态", lambda row: row.status),
            ("文件夹标题", lambda row: row.folder_title), ("Metadata 标题", lambda row: row.title),
            ("groupName", lambda row: row.group_name), ("详情", lambda row: row.detail),
        ), "开始检查")
        self._database, self._settings = database, settings
        self._root = Path(settings.load().library_path) if settings.load().library_path else None
        self.action_button.clicked.connect(self.analyze)
        self.group_combo = QComboBox(); self.group_combo.setEditable(True); self.group_combo.addItems(("下载", "归档"))
        self.group_combo.setMinimumWidth(180)
        update = QPushButton("修改选中 groupName"); update.clicked.connect(self.update_selected)
        self.add_control_bar(self.group_combo, update)

    def set_library_root(self, value: str) -> None: self._root = Path(value) if value else None
    def analyze(self) -> None:
        if not self._root: QMessageBox.warning(self, "Metadata", "请先完成库扫描。"); return
        self.run_worker(analyze_metadata(self._database, self._root), "正在检查 Metadata…")

    def update_selected(self) -> None:
        selection = self.table.selectionModel().selectedRows() if self.table.selectionModel() else []
        rows = [self.model.row(index) for index in selection]
        items = [row for row in rows if isinstance(row, MetadataIssue) and row.status != "缺失" and row.folder.is_dir()]
        value = self.group_combo.currentText().strip()
        if not items or not value: QMessageBox.information(self, "Metadata", "请选择文件夹载体中存在的 metadata/ametadata 行；CBZ 内 Metadata 当前仅支持只读检查。"); return
        if QMessageBox.question(self, "确认修改", f"将备份并修改 {len(items)} 个文件的 groupName，是否继续？") != QMessageBox.StandardButton.Yes: return
        backup_root = (self._root or Path.cwd()) / "metadata_backup"
        def action(progress, cancelled):
            result = FeatureResult(); service = MetadataService()
            for index, item in enumerate(items, 1):
                if cancelled(): break
                source = item.folder / item.file_name
                try:
                    backup = service.update_group_name(item.folder, item.file_name, value, backup_root)
                    self._database.log_operation("Metadata groupName", "成功", source, backup); result.success += 1
                except Exception as error:
                    self._database.log_operation("Metadata groupName", "失败", source, backup_root, str(error)); result.failed += 1
                progress(index, len(items), item.folder.name)
            return result
        self.run_worker(action, "正在备份并修改 Metadata…", lambda result: self._done(result))

    def _done(self, result: FeatureResult) -> None:
        self.task.status.setText(f"完成 · 成功 {result.success} · 失败 {result.failed}")
        QMessageBox.information(self, "Metadata", f"{self.task.status.text()}\n备份位于漫画库 metadata_backup。")
