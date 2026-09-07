from __future__ import annotations

from pathlib import Path

from PySide6.QtWidgets import QCheckBox, QMessageBox, QPushButton

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
        metadata_group = QPushButton("metadata → 下载")
        metadata_group.clicked.connect(lambda: self.update_selected("metadata", "下载"))
        ametadata_group = QPushButton("ametadata → 归档")
        ametadata_group.clicked.connect(lambda: self.update_selected("ametadata", "归档"))
        self.include_comic_info = QCheckBox("备份包含 ComicInfo.xml")
        backup = QPushButton("备份选中目录")
        backup.clicked.connect(self.backup_selected)
        self.add_control_bar(metadata_group, ametadata_group, self.include_comic_info, backup)

    def set_library_root(self, value: str) -> None: self._root = Path(value) if value else None
    def analyze(self) -> None:
        if not self._root: QMessageBox.warning(self, "Metadata", "请先完成库扫描。"); return
        self.run_worker(analyze_metadata(self._database, self._root), "正在检查 Metadata…", allow_pause=True)

    def update_selected(self, file_name: str, value: str) -> None:
        selection = self.table.selectionModel().selectedRows() if self.table.selectionModel() else []
        rows = [self.model.row(index) for index in selection]
        items = [
            row for row in rows
            if isinstance(row, MetadataIssue)
            and row.file_name == file_name
            and row.status != "缺失"
            and row.folder.is_dir()
        ]
        if not items:
            QMessageBox.information(self, "Metadata", f"请选择文件夹载体中存在的 {file_name} 行；CBZ 内 Metadata 当前仅支持只读检查。")
            return
        if QMessageBox.question(self, "确认修改", f"将备份并把 {len(items)} 个 {file_name} 的 groupName 修改为“{value}”，是否继续？") != QMessageBox.StandardButton.Yes: return
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
        self.run_worker(action, "正在备份并修改 Metadata…", lambda result: self._done(result), allow_pause=True)

    def backup_selected(self) -> None:
        selection = self.table.selectionModel().selectedRows() if self.table.selectionModel() else []
        folders = {
            row.folder
            for index in selection
            if isinstance((row := self.model.row(index)), MetadataIssue) and row.folder.is_dir()
        }
        if not folders:
            QMessageBox.information(self, "Metadata", "请选择一个或多个文件夹载体；CBZ 当前仅支持只读检查。")
            return
        include_comic_info = self.include_comic_info.isChecked()
        if QMessageBox.question(self, "确认备份", f"将备份 {len(folders)} 个目录中的 Metadata" + (" 和 ComicInfo.xml" if include_comic_info else "") + "，是否继续？") != QMessageBox.StandardButton.Yes:
            return
        backup_root = (self._root or Path.cwd()) / "metadata_backup"

        def action(progress, cancelled):
            result = FeatureResult(); service = MetadataService()
            for index, folder in enumerate(sorted(folders), 1):
                if cancelled(): break
                try:
                    backups = service.backup_files(folder, backup_root, include_comic_info=include_comic_info)
                    self._database.log_operation("Metadata 备份", "成功", folder, backup_root)
                    if backups: result.success += 1
                    else: result.skipped += 1
                except Exception as error:
                    self._database.log_operation("Metadata 备份", "失败", folder, backup_root, str(error)); result.failed += 1
                progress(index, len(folders), folder.name)
            return result

        self.run_worker(action, "正在备份 Metadata…", lambda result: self._done(result), allow_pause=True)

    def _done(self, result: FeatureResult) -> None:
        self.task.status.setText(f"完成 · 成功 {result.success} · 失败 {result.failed} · 跳过 {result.skipped}")
        QMessageBox.information(self, "Metadata", f"{self.task.status.text()}\n备份位于漫画库 metadata_backup。")
