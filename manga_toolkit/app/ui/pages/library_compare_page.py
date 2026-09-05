from __future__ import annotations

from pathlib import Path
from PySide6.QtWidgets import QCheckBox, QFileDialog, QLineEdit, QMessageBox

from app.services.database_service import DatabaseService
from app.services.settings_service import SettingsService
from app.ui.pages.feature_base_page import FeatureBasePage
from app.workers.feature_workers import compare_libraries


class LibraryComparePage(FeatureBasePage):
    def __init__(self, database: DatabaseService, settings: SettingsService) -> None:
        super().__init__("库对比", "比较已扫描库 A 与另一个目录 B；默认仅比较同类型 ID", (
            ("ID", lambda row: row.gallery_id), ("类型", lambda row: row.gallery_type), ("状态", lambda row: row.status),
            ("A 名称", lambda row: row.name_a), ("B 名称", lambda row: row.name_b),
            ("A 路径", lambda row: row.path_a), ("B 路径", lambda row: row.path_b),
        ), "开始对比")
        self._database = database
        configured = settings.load().library_path; self._root = Path(configured) if configured else None
        self.path_b = QLineEdit(); self.path_b.setPlaceholderText("选择库 B")
        self.path_b.setMinimumWidth(420)
        from PySide6.QtWidgets import QPushButton
        browse = QPushButton("选择 B"); browse.clicked.connect(self.select_b)
        self.cross = QCheckBox("Normal ↔ Archive")
        self.add_control_bar(self.path_b, browse, self.cross)
        self.action_button.clicked.connect(self.compare)
    def set_library_root(self, value: str) -> None: self._root = Path(value) if value else None
    def select_b(self) -> None:
        value = QFileDialog.getExistingDirectory(self, "选择库 B")
        if value: self.path_b.setText(value)
    def compare(self) -> None:
        root_b = Path(self.path_b.text().strip()) if self.path_b.text().strip() else None
        if not self._root or not root_b: QMessageBox.warning(self, "库对比", "请先扫描库 A 并选择库 B。"); return
        self.run_worker(compare_libraries(self._database, self._root, root_b, self.cross.isChecked()), "正在扫描并对比库 B…")
