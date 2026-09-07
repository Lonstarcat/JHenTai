from __future__ import annotations

from pathlib import Path

from PySide6.QtWidgets import (
    QAbstractItemView,
    QCheckBox,
    QFileDialog,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QTableView,
    QTabWidget,
)

from app.models.gallery_folder import GalleryFolder
from app.models.toolkit_features import FeatureResult, LibraryComparison, LibraryMatchPlan, PlanStatus
from app.services.database_service import DatabaseService
from app.services.library_compare_service import LibraryCompareService
from app.services.library_match_service import LibraryMatchService
from app.services.scanner_service import LibraryScannerService
from app.services.settings_service import SettingsService
from app.ui.feature_table_model import FeatureTableModel
from app.ui.pages.feature_base_page import FeatureBasePage
from app.ui.table_interactions import install_table_interactions
from app.ui.widgets.numeric_inputs import NoWheelSpinBox


class LibraryComparePage(FeatureBasePage):
    def __init__(self, database: DatabaseService, settings: SettingsService) -> None:
        super().__init__("库对比", "比较库 A/B，并通过确认后的 Excel 精确移动库 B 项目", (
            ("ID", lambda row: row.gallery_id), ("类型", lambda row: row.gallery_type), ("状态", lambda row: row.status),
            ("A 名称", lambda row: row.name_a), ("B 名称", lambda row: row.name_b),
            ("A 大小", lambda row: self._format_size(row.size_a)), ("B 大小", lambda row: self._format_size(row.size_b)),
            ("保留建议", lambda row: row.recommendation),
            ("A 路径", lambda row: row.path_a), ("B 路径", lambda row: row.path_b),
        ), "开始对比")
        self._database = database
        configured = settings.load().library_path
        self._root = Path(configured) if configured else None
        self._right_cache_root: Path | None = None
        self._right_cache: list[GalleryFolder] = []
        self._imported_plan = False

        self.match_model = FeatureTableModel((
            ("执行", lambda row: "是" if row.execute else "否"),
            ("状态", lambda row: row.status.value),
            ("ID", lambda row: row.gallery_id),
            ("A 类型", lambda row: row.type_a),
            ("B 类型", lambda row: row.type_b),
            ("A 名称", lambda row: row.name_a),
            ("B 名称", lambda row: row.name_b),
            ("B 路径", lambda row: row.path_b),
            ("目标路径", lambda row: row.target_path),
            ("备注", lambda row: row.note),
        ))
        self.layout.removeWidget(self.table)
        self.tabs = QTabWidget()
        self.tabs.addTab(self.table, "库对比结果")
        self.match_table = QTableView()
        self.match_table.setModel(self.match_model)
        self.match_table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.match_table.setSelectionMode(QAbstractItemView.SelectionMode.ExtendedSelection)
        self.match_table.setAlternatingRowColors(True)
        self.match_table.setShowGrid(False)
        self.match_table.verticalHeader().setVisible(False)
        self.match_table.verticalHeader().setDefaultSectionSize(40)
        self.match_table.horizontalHeader().setStretchLastSection(True)
        install_table_interactions(self.match_table)
        self.tabs.addTab(self.match_table, "A ID → B 操作计划")
        self.layout.addWidget(self.tabs, 1)

        self.path_b = QLineEdit(); self.path_b.setPlaceholderText("选择库 B"); self.path_b.setMinimumWidth(360)
        browse_b = QPushButton("选择 B"); browse_b.clicked.connect(self.select_b)
        self.cross = QCheckBox("Normal ↔ Archive")
        self.archive_threshold = NoWheelSpinBox()
        self.archive_threshold.setRange(1, 10240)
        self.archive_threshold.setValue(50)
        self.archive_threshold.setToolTip("Archive 保留建议阈值，单位 MB；仅用于跨类型 ID 匹配")
        threshold_label = QLabel("Archive 阈值（MB）")
        refresh_b = QPushButton("刷新 B 缓存"); refresh_b.clicked.connect(self.clear_b_cache)
        self.add_control_bar(self.path_b, browse_b, self.cross, threshold_label, self.archive_threshold, refresh_b)

        self.destination = QLineEdit(); self.destination.setPlaceholderText("B 中匹配项目的目标目录"); self.destination.setMinimumWidth(320)
        browse_destination = QPushButton("选择目标"); browse_destination.clicked.connect(self.select_destination)
        generate = QPushButton("生成 A→B 计划"); generate.clicked.connect(self.generate_match_plan)
        export_plan = QPushButton("导出计划 Excel"); export_plan.clicked.connect(self.export_match_plan)
        import_plan = QPushButton("导入确认 Excel"); import_plan.clicked.connect(self.import_match_plan)
        execute = QPushButton("执行导入计划"); execute.clicked.connect(self.execute_imported_plan)
        self.cancel_button = QPushButton("取消"); self.cancel_button.setEnabled(False); self.cancel_button.clicked.connect(self.cancel_task)
        self.add_control_bar(self.destination, browse_destination, generate, export_plan, import_plan, execute, self.cancel_button)
        self.action_button.clicked.connect(self.compare)

    def set_library_root(self, value: str) -> None:
        self._root = Path(value) if value else None

    def select_b(self) -> None:
        value = QFileDialog.getExistingDirectory(self, "选择库 B")
        if value:
            self.path_b.setText(value)
            self.clear_b_cache()

    def select_destination(self) -> None:
        value = QFileDialog.getExistingDirectory(self, "选择匹配项目目标目录")
        if value:
            self.destination.setText(value)

    def clear_b_cache(self) -> None:
        self._right_cache_root = None
        self._right_cache = []
        self.task.status.setText("库 B 缓存已清除；下次操作会重新扫描")

    def compare(self) -> None:
        if self._thread is not None:
            return
        root_b = self._validated_b_root()
        if root_b is None:
            return
        self._with_library_b(
            root_b,
            lambda right: LibraryCompareService().compare(
                self._database.list_galleries(self._root),
                right,
                self.cross.isChecked(),
                self.archive_threshold.value() * 1024 * 1024,
            ),
            "正在扫描并对比库 B…",
            self._comparison_completed,
        )

    def generate_match_plan(self) -> None:
        if self._thread is not None:
            return
        root_b = self._validated_b_root()
        destination = self._validated_destination()
        if root_b is None or destination is None:
            return
        self._with_library_b(
            root_b,
            lambda right: LibraryMatchService().build_plans(
                self._database.list_galleries(self._root), right, destination, cross_type=self.cross.isChecked()
            ),
            "正在生成 A ID → B 匹配计划…",
            self._match_plan_completed,
        )

    def _with_library_b(self, root_b: Path, compute, label: str, completed) -> None:
        cached = self._right_cache_root == root_b and bool(self._right_cache)

        def action(progress, cancelled):
            if cached:
                right = self._right_cache
            else:
                scanned = LibraryScannerService().scan(root_b, on_progress=progress, is_cancelled=cancelled)
                if cancelled():
                    return None
                right = [item.gallery for item in scanned if item.gallery is not None]
            return right, compute(right)

        def done(payload) -> None:
            if payload is None:
                self.task.status.setText("库 B 扫描已取消；未保存不完整缓存")
                return
            right, result = payload
            self._right_cache_root = root_b
            self._right_cache = right
            completed(result)

        self.cancel_button.setEnabled(True)
        self.run_worker(action, label, done, allow_pause=True)

    def _comparison_completed(self, rows: list[LibraryComparison]) -> None:
        self.model.set_rows(rows)
        self.tabs.setCurrentIndex(0)
        only_a = sum(row.status == "仅 A 存在" for row in rows)
        only_b = sum(row.status == "仅 B 存在" for row in rows)
        renamed = sum(row.status == "ID 相同名称不同" for row in rows)
        self.task.status.setText(f"对比完成 · 仅 A {only_a} · 仅 B {only_b} · 同 ID 异名 {renamed}")

    def _match_plan_completed(self, plans: list[LibraryMatchPlan]) -> None:
        self.match_model.set_rows(plans)
        self._imported_plan = False
        self.tabs.setCurrentIndex(1)
        conflicts = sum(plan.status is not PlanStatus.READY for plan in plans)
        self.task.status.setText(f"匹配计划完成 · {len(plans)} 项 · 冲突 {conflicts}；导出后把需要执行的行改为“是”")

    def export_match_plan(self) -> None:
        plans = [row for row in self.match_model.rows if isinstance(row, LibraryMatchPlan)]
        if not plans:
            QMessageBox.information(self, "导出匹配计划", "请先生成 A ID → B 匹配计划。")
            return
        value, _ = QFileDialog.getSaveFileName(self, "导出匹配计划", "A到B匹配移动计划.xlsx", "Excel (*.xlsx)")
        if not value:
            return
        destination = Path(value if value.casefold().endswith(".xlsx") else value + ".xlsx")
        self.run_worker(
            lambda progress, cancelled: LibraryMatchService().export_plan(plans, destination),
            "正在导出匹配计划…",
            lambda _: QMessageBox.information(self, "导出完成", f"{destination}\n请核对路径，并只把确认移动的行“执行”列改为“是”。"),
        )

    def import_match_plan(self) -> None:
        if self._thread is not None:
            return
        root_b = self._validated_b_root()
        destination = self._validated_destination()
        if root_b is None or destination is None:
            return
        value, _ = QFileDialog.getOpenFileName(self, "导入确认后的匹配计划", "", "Excel (*.xlsx)")
        if not value:
            return

        def completed(plans: list[LibraryMatchPlan]) -> None:
            self.match_model.set_rows(plans)
            self._imported_plan = True
            self.tabs.setCurrentIndex(1)
            ready = sum(plan.status is PlanStatus.READY for plan in plans)
            self.task.status.setText(f"已导入确认计划 · 执行行 {len(plans)} · 可执行 {ready} · 异常 {len(plans) - ready}")

        self.run_worker(
            lambda progress, cancelled: LibraryMatchService().import_confirmed_plan(Path(value), root_b, destination),
            "正在读取并验证 Excel 操作计划…",
            completed,
        )

    def execute_imported_plan(self) -> None:
        if self._thread is not None:
            return
        if not self._imported_plan:
            QMessageBox.warning(self, "执行计划", "只能执行从确认后 Excel 导入的计划；页面刚生成的匹配结果不能直接执行。")
            return
        plans = [
            row for row in self.match_model.rows
            if isinstance(row, LibraryMatchPlan) and row.execute and row.status is PlanStatus.READY
        ]
        if not plans:
            QMessageBox.information(self, "执行计划", "没有状态为 ready 且“执行=是”的记录。")
            return
        preview = "\n".join(f"{plan.path_b} → {plan.target_path}" for plan in plans[:20])
        if len(plans) > 20:
            preview += f"\n……另有 {len(plans) - 20} 项"
        box = QMessageBox(self)
        box.setWindowTitle("确认执行 Excel 移动计划")
        box.setIcon(QMessageBox.Icon.Warning)
        box.setText(f"将严格按 Excel 中的固定路径移动 {len(plans)} 个库 B 项目。不会重新匹配，也不会覆盖目标。")
        box.setDetailedText(preview)
        box.setStandardButtons(QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel)
        box.setDefaultButton(QMessageBox.StandardButton.Cancel)
        if box.exec() != QMessageBox.StandardButton.Yes:
            return

        def action(progress, cancelled):
            result = FeatureResult(); service = LibraryMatchService()
            for index, plan in enumerate(plans, 1):
                if cancelled():
                    result.cancelled = True
                    break
                try:
                    service.execute(plan)
                    self._database.log_operation("Excel 驱动移动 B", "成功", plan.path_b, plan.target_path)
                    result.success += 1
                except Exception as error:
                    self._database.log_operation("Excel 驱动移动 B", "失败", plan.path_b, plan.target_path, str(error))
                    result.failed += 1
                progress(index, len(plans), plan.name_b)
            return result

        self.cancel_button.setEnabled(True)
        self.run_worker(action, "正在按 Excel 移动库 B 项目…", self._execution_completed, allow_pause=True)

    def _execution_completed(self, result: FeatureResult) -> None:
        state = "已取消" if result.cancelled else "完成"
        self.task.status.setText(f"{state} · 成功 {result.success} · 失败 {result.failed}")
        self._right_cache_root = None
        self._right_cache = []
        QMessageBox.information(self, "Excel 移动计划", self.task.status.text() + "\n请重新扫描相关漫画库。")

    def cancel_task(self) -> None:
        self.stop()
        self.cancel_button.setEnabled(False)
        self.task.status.setText("正在安全停止当前库对比任务…")

    def _validated_b_root(self) -> Path | None:
        if self._root is None:
            QMessageBox.warning(self, "库对比", "请先完成库 A 扫描。")
            return None
        value = self.path_b.text().strip()
        if not value:
            QMessageBox.warning(self, "库对比", "请选择库 B。")
            return None
        root_b = Path(value)
        if not root_b.is_dir():
            QMessageBox.warning(self, "库对比", "库 B 路径不存在或不是目录。")
            return None
        return root_b

    def _validated_destination(self) -> Path | None:
        value = self.destination.text().strip()
        if not value:
            QMessageBox.warning(self, "库对比", "请选择 B 中匹配项目的目标目录。")
            return None
        return Path(value)

    def _thread_finished(self) -> None:
        super()._thread_finished()
        self.cancel_button.setEnabled(False)

    @staticmethod
    def _format_size(value: int) -> str:
        return f"{value / 1024 / 1024:.1f} MB" if value else "—"
