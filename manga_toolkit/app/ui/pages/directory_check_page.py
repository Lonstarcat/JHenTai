from __future__ import annotations

from pathlib import Path
from PySide6.QtWidgets import QMessageBox

from app.services.database_service import DatabaseService
from app.services.settings_service import SettingsService
from app.ui.pages.feature_base_page import FeatureBasePage
from app.workers.feature_workers import check_directories


class DirectoryCheckPage(FeatureBasePage):
    def __init__(self, database: DatabaseService, settings: SettingsService) -> None:
        super().__init__("目录检查", "只读检查异常文件、子文件夹和缺少图片；不会自动删除", (
            ("ID", lambda row: row.gallery_id), ("漫画目录", lambda row: row.folder),
            ("异常类型", lambda row: row.issue_type), ("异常项", lambda row: row.item), ("说明", lambda row: row.detail),
        ), "开始检查")
        self._database = database
        configured = settings.load().library_path; self._root = Path(configured) if configured else None
        self.action_button.clicked.connect(self.run_check)
    def set_library_root(self, value: str) -> None: self._root = Path(value) if value else None
    def run_check(self) -> None:
        if not self._root: QMessageBox.warning(self, "目录检查", "请先完成库扫描。"); return
        self.run_worker(check_directories(self._database, self._root), "正在检查目录…", allow_pause=True)
