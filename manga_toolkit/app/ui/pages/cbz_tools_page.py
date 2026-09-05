from __future__ import annotations

from pathlib import Path

from PySide6.QtWidgets import QComboBox, QFileDialog, QLineEdit, QMessageBox, QPushButton

from app.models.toolkit_features import FeatureResult
from app.services.database_service import DatabaseService
from app.services.settings_service import SettingsService
from app.ui.pages.feature_base_page import FeatureBasePage
from app.workers.feature_workers import check_cbz, pack_cbz


class CbzToolsPage(FeatureBasePage):
    def __init__(self, database: DatabaseService, settings: SettingsService) -> None:
        super().__init__("CBZ 工具", "使用 7‑Zip Store 模式批量打包；支持断点跳过与完整性检查", (
            ("状态", lambda row: row.status.value), ("原目录", lambda row: row.folder), ("CBZ", lambda row: row.cbz_path),
            ("原文件数", lambda row: row.source_count), ("包内文件数", lambda row: row.archive_count), ("详情", lambda row: row.detail),
        ), "完整性检查")
        self._database, self._settings = database, settings
        configured = settings.load().library_path; self._root = Path(configured) if configured else None
        self.output = QLineEdit(); self.output.setPlaceholderText("CBZ 输出目录")
        self.output.setMinimumWidth(420)
        browse = QPushButton("选择输出目录"); browse.clicked.connect(self.select_output)
        self.compression = QComboBox(); self.compression.addItem("Store", 0); self.compression.addItem("Fast", 1); self.compression.addItem("Normal", 5); self.compression.addItem("Maximum", 9)
        self.concurrency = QComboBox()
        for count in range(1, 9): self.concurrency.addItem(f"并发 {count}", count)
        self.concurrency.setCurrentIndex(2)
        self.pack_button = QPushButton("开始打包"); self.pack_button.clicked.connect(self.pack)
        self.add_control_bar(self.output, browse, self.compression, self.concurrency, self.pack_button)
        self.action_button.clicked.connect(self.check)
    def set_library_root(self, value: str) -> None: self._root = Path(value) if value else None
    def select_output(self) -> None:
        value = QFileDialog.getExistingDirectory(self, "选择 CBZ 输出目录")
        if value: self.output.setText(value)
    def _paths(self) -> tuple[Path, Path] | None:
        output = Path(self.output.text().strip()) if self.output.text().strip() else None
        if not self._root or not output: QMessageBox.warning(self, "CBZ 工具", "请先扫描漫画库并选择输出目录。"); return None
        return self._root, output
    def check(self) -> None:
        paths = self._paths()
        if paths: self.run_worker(check_cbz(self._database, *paths), "正在检查 CBZ…")
    def pack(self) -> None:
        paths = self._paths()
        if not paths: return
        configured = self._settings.load().seven_zip_path
        seven_zip = Path(configured) if configured else None
        if not seven_zip or not seven_zip.is_file(): QMessageBox.warning(self, "CBZ 工具", "请先在设置中配置有效的 7z.exe。"); return
        if QMessageBox.question(self, "确认批量打包", "将为扫描缓存中的漫画生成 CBZ。已有文件会跳过，源目录不会删除，是否继续？") != QMessageBox.StandardButton.Yes: return
        self.pack_button.setEnabled(False)
        self.run_worker(pack_cbz(self._database, *paths, seven_zip, int(self.compression.currentData()), int(self.concurrency.currentData())), "正在批量打包…", self._packed)
    def _packed(self, result: FeatureResult) -> None:
        self.pack_button.setEnabled(True)
        self.task.status.setText(f"完成 · 成功 {result.success} · 失败 {result.failed} · 跳过 {result.skipped}")
        QMessageBox.information(self, "CBZ 打包", self.task.status.text())

    def _thread_finished(self) -> None:
        super()._thread_finished(); self.pack_button.setEnabled(True)
