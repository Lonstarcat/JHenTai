from __future__ import annotations

from pathlib import Path

from PySide6.QtWidgets import QFileDialog, QLineEdit, QMessageBox, QPushButton

from app.models.toolkit_features import FeatureResult, PlanStatus, RenamePlan
from app.services.database_service import DatabaseService
from app.services.name_organizer_service import NameOrganizerService
from app.services.settings_service import SettingsService
from app.ui.pages.feature_base_page import FeatureBasePage
from app.workers.feature_workers import analyze_names


class NameOrganizerPage(FeatureBasePage):
    def __init__(self, database: DatabaseService, settings: SettingsService) -> None:
        super().__init__("名称整理", "按同类型同 ID 生成 Short / Long 分类计划；执行前预览且不覆盖", (
            ("ID", lambda row: row.gallery_id), ("状态", lambda row: row.status.value),
            ("原路径", lambda row: row.source), ("目标路径", lambda row: row.target), ("原因", lambda row: row.reason),
        ), "生成分类计划")
        self._database, self._settings = database, settings
        self._root = Path(settings.load().library_path) if settings.load().library_path else None
        self.action_button.clicked.connect(self.analyze)
        self.output = QLineEdit(); self.output.setPlaceholderText("分类输出目录")
        self.output.setMinimumWidth(420)
        browse = QPushButton("选择目录"); browse.clicked.connect(self.select_output)
        sync = QPushButton("生成名称同步计划"); sync.clicked.connect(self.analyze_sync)
        self.execute_button = QPushButton("执行移动计划")
        self.execute_button.clicked.connect(self.execute)
        self.add_control_bar(self.output, browse, sync, self.execute_button)

    def set_library_root(self, value: str) -> None: self._root = Path(value) if value else None

    def select_output(self) -> None:
        value = QFileDialog.getExistingDirectory(self, "选择分类输出目录")
        if value: self.output.setText(value)

    def analyze(self) -> None:
        if not self._root: QMessageBox.warning(self, "名称整理", "请先完成库扫描。"); return
        output = Path(self.output.text().strip()) if self.output.text().strip() else self._root.parent / "处理中"
        self.output.setText(str(output))
        self.run_worker(analyze_names(self._database, self._root, output), "正在生成分类计划…")

    def analyze_sync(self) -> None:
        output = Path(self.output.text().strip()) if self.output.text().strip() else None
        if not output:
            QMessageBox.warning(self, "名称整理", "请先选择包含 Normal_ID / Archive_ID 的分类目录。")
            return
        self.run_worker(
            lambda progress, cancelled: NameOrganizerService().build_sync_plans(output),
            "正在生成名称同步计划…",
        )

    def execute(self) -> None:
        plans = [row for row in self.model.rows if isinstance(row, RenamePlan) and row.status is PlanStatus.READY]
        if not plans: QMessageBox.information(self, "名称整理", "没有可执行计划。"); return
        if QMessageBox.question(self, "确认执行", f"将按当前预览移动或重命名 {len(plans)} 个目录，原路径将不再保留；不会覆盖目标，也不会永久删除文件。是否继续？") != QMessageBox.StandardButton.Yes: return
        def action(progress, cancelled):
            result = FeatureResult(); service = NameOrganizerService()
            for index, plan in enumerate(plans, 1):
                if cancelled(): break
                try:
                    operation = "名称同步" if "同步" in plan.reason else "名称分类移动"
                    service.execute(plan); self._database.log_operation(operation, "成功", plan.source, plan.target); result.success += 1
                except Exception as error:
                    operation = "名称同步" if "同步" in plan.reason else "名称分类移动"
                    self._database.log_operation(operation, "失败", plan.source, plan.target, str(error)); result.failed += 1
                progress(index, len(plans), plan.source.name)
            return result
        self.run_worker(action, "正在安全移动…", lambda result: self._after_execute(result), allow_pause=True)

    def _after_execute(self, result: FeatureResult) -> None:
        self.task.status.setText(f"完成 · 成功 {result.success} · 失败 {result.failed}")
        QMessageBox.information(self, "名称整理", self.task.status.text())
