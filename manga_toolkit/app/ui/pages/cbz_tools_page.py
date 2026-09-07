from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import Signal
from PySide6.QtWidgets import QComboBox, QFileDialog, QLineEdit, QMessageBox, QPushButton

from app.models.toolkit_features import (
    CbzCheckResult,
    CbzStatus,
    ExistingCbzPolicy,
    FeatureResult,
    IsolationMode,
    PlanStatus,
)
from app.services.database_service import DatabaseService
from app.services.cbz_organize_service import CbzOrganizeService
from app.services.isolation_service import IsolationService
from app.services.settings_service import SettingsService
from app.ui.pages.feature_base_page import FeatureBasePage
from app.workers.feature_workers import check_cbz, pack_cbz


class CbzToolsPage(FeatureBasePage):
    cbz_counts_changed = Signal(int, int)

    def __init__(self, database: DatabaseService, settings: SettingsService) -> None:
        super().__init__("CBZ 工具", "使用 7‑Zip Store 模式批量打包；支持断点跳过与完整性检查", (
            ("状态", lambda row: row.status.value), ("原目录", lambda row: row.folder), ("CBZ", lambda row: row.cbz_path),
            ("原文件数", lambda row: row.source_count), ("包内文件数", lambda row: row.archive_count), ("详情", lambda row: row.detail),
        ), "完整性检查")
        self._database, self._settings = database, settings
        self._all_results: list[CbzCheckResult] = []
        configured = settings.load().library_path; self._root = Path(configured) if configured else None
        self.output = QLineEdit(); self.output.setPlaceholderText("CBZ 输出目录")
        self.output.setMinimumWidth(420)
        browse = QPushButton("选择输出目录"); browse.clicked.connect(self.select_output)
        self.compression = QComboBox(); self.compression.addItem("Store", 0); self.compression.addItem("Fast", 1); self.compression.addItem("Normal", 5); self.compression.addItem("Maximum", 9)
        self.concurrency = QComboBox()
        for count in range(1, 9): self.concurrency.addItem(f"并发 {count}", count)
        self.concurrency.setCurrentIndex(2)
        self.limit = QComboBox()
        for label, value in (("测试前 10 个", 10), ("测试前 50 个", 50), ("测试前 100 个", 100), ("全部", None)):
            self.limit.addItem(label, value)
        self.limit.setCurrentIndex(3)
        self.existing_policy = QComboBox()
        for policy in ExistingCbzPolicy:
            self.existing_policy.addItem(f"已有：{policy.value}", policy.value)
        self.pack_button = QPushButton("开始打包"); self.pack_button.clicked.connect(self.pack)
        self.pause_button = QPushButton("暂停")
        self.pause_button.setEnabled(False)
        self.pause_button.clicked.connect(self.toggle_pause)
        self.cancel_button = QPushButton("取消任务")
        self.cancel_button.setEnabled(False)
        self.cancel_button.clicked.connect(self.cancel_current)
        self.add_control_bar(self.output, browse, self.compression, self.concurrency, self.limit, self.existing_policy, self.pack_button, self.pause_button, self.cancel_button)
        self.status_filter = QComboBox()
        self.status_filter.addItem("全部", "")
        self.status_filter.addItem("所有异常", "__issues__")
        for status in CbzStatus:
            self.status_filter.addItem(status.value, status.value)
        self.status_filter.currentIndexChanged.connect(self.apply_status_filter)
        self.folder_isolation_mode = QComboBox()
        self.folder_isolation_mode.addItem("原目录：复制", IsolationMode.COPY.value)
        self.folder_isolation_mode.addItem("原目录：移动", IsolationMode.MOVE.value)
        self.cbz_isolation_mode = QComboBox()
        self.cbz_isolation_mode.addItem("CBZ：复制", IsolationMode.COPY.value)
        self.cbz_isolation_mode.addItem("CBZ：移动", IsolationMode.MOVE.value)
        isolate = QPushButton("隔离缺少 ComicInfo")
        isolate.clicked.connect(self.isolate_missing_comic_info)
        self.add_control_bar(self.status_filter, self.folder_isolation_mode, self.cbz_isolation_mode, isolate)
        self.organize_mode = QComboBox()
        self.organize_mode.addItem("同名目录：复制", IsolationMode.COPY.value)
        self.organize_mode.addItem("同名目录：移动", IsolationMode.MOVE.value)
        organize = QPushButton("整理 CBZ 到同名目录")
        organize.clicked.connect(self.organize_cbz_files)
        self.add_control_bar(self.organize_mode, organize)
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
        if self._thread is not None:
            return
        paths = self._paths()
        if paths:
            self.cancel_button.setEnabled(True)
            self.run_worker(check_cbz(self._database, *paths), "正在检查 CBZ…", self._checked, allow_pause=True)
    def pack(self) -> None:
        if self._thread is not None:
            return
        paths = self._paths()
        if not paths: return
        configured = self._settings.load().seven_zip_path
        seven_zip = Path(configured) if configured else None
        if not seven_zip or not seven_zip.is_file(): QMessageBox.warning(self, "CBZ 工具", "请先在设置中配置有效的 7z.exe。"); return
        policy = ExistingCbzPolicy(str(self.existing_policy.currentData()))
        limit_value = self.limit.currentData()
        limit_text = self.limit.currentText()
        policy_hint = {
            ExistingCbzPolicy.SKIP: "已有 CBZ 会跳过。",
            ExistingCbzPolicy.REBUILD: "已有 CBZ 会先备份到 cbz_backup，再用新包替换。",
            ExistingCbzPolicy.VERIFY: "已有 CBZ 先完整验证；正常则跳过，异常则备份后重建。",
        }[policy]
        if QMessageBox.question(self, "确认批量打包", f"范围：{limit_text}。{policy_hint}\n源漫画目录不会删除，是否继续？") != QMessageBox.StandardButton.Yes: return
        self.pack_button.setEnabled(False)
        self.pause_button.setEnabled(True)
        self.cancel_button.setEnabled(True)
        self.pause_button.setText("暂停")
        self.run_worker(
            pack_cbz(
                self._database,
                *paths,
                seven_zip,
                int(self.compression.currentData()),
                int(self.concurrency.currentData()),
                policy,
                int(limit_value) if limit_value is not None else None,
            ),
            "正在批量打包…",
            self._packed,
        )
    def _packed(self, result: FeatureResult) -> None:
        self.pack_button.setEnabled(True)
        state = "已取消" if result.cancelled else "完成"
        self.task.status.setText(f"{state} · 成功 {result.success} · 失败 {result.failed} · 跳过 {result.skipped}")
        QMessageBox.information(self, "CBZ 打包", self.task.status.text())

    def toggle_pause(self) -> None:
        if self._thread is None:
            return
        if self.is_paused:
            self.resume()
            self.pause_button.setText("暂停")
            self.task.status.setText("正在继续调度；等待当前任务状态更新…")
        else:
            self.pause()
            self.pause_button.setText("继续")
            self.task.status.setText("已暂停调度；正在执行的 7-Zip 任务完成后停止投放")

    def cancel_current(self) -> None:
        if self._thread is None:
            return
        self.stop()
        self.cancel_button.setEnabled(False)
        self.task.status.setText("正在安全停止；等待已启动的 7-Zip 或当前检查项完成…")

    def _checked(self, results: list[CbzCheckResult]) -> None:
        self._all_results = results
        self.apply_status_filter()
        missing = sum(item.status is CbzStatus.MISSING for item in results)
        extra = sum(item.status is CbzStatus.EXTRA for item in results)
        invalid = sum(item.status is not CbzStatus.VALID for item in results)
        existing = [item for item in results if item.cbz_path.exists()]
        self.cbz_counts_changed.emit(
            len(existing),
            sum(item.status is not CbzStatus.VALID for item in existing),
        )
        self.task.status.setText(f"检查完成 · 原目录 {len(results) - extra} · 缺少 CBZ {missing} · 多余 CBZ {extra} · 异常 {invalid}")

    def apply_status_filter(self) -> None:
        selected = str(self.status_filter.currentData() or "")
        if not selected:
            rows = self._all_results
        elif selected == "__issues__":
            rows = [item for item in self._all_results if item.status is not CbzStatus.VALID]
        else:
            rows = [item for item in self._all_results if item.status.value == selected]
        self.model.set_rows(rows)

    def isolate_missing_comic_info(self) -> None:
        if self._thread is not None:
            return
        if not self._root:
            QMessageBox.warning(self, "CBZ 工具", "请先完成库扫描。")
            return
        output = Path(self.output.text().strip()) if self.output.text().strip() else None
        if output is None:
            QMessageBox.warning(self, "CBZ 工具", "请先选择 CBZ 输出目录并完成完整性检查。")
            return
        service = IsolationService()
        plans = service.build_plans(
            self._all_results,
            self._root.parent / "缺少ComicInfo",
            output.parent / "缺少ComicInfo_CBZ",
            folder_mode=IsolationMode(str(self.folder_isolation_mode.currentData())),
            cbz_mode=IsolationMode(str(self.cbz_isolation_mode.currentData())),
        )
        ready = [plan for plan in plans if plan.status is PlanStatus.READY]
        conflicts = len(plans) - len(ready)
        if not plans:
            QMessageBox.information(self, "缺少 ComicInfo 隔离", "当前检查结果中没有可隔离的缺少 ComicInfo 项。")
            return
        preview = "\n".join(f"{plan.mode.value} {plan.item_type}：{plan.source} → {plan.target}" for plan in plans[:20])
        if len(plans) > 20:
            preview += f"\n……另有 {len(plans) - 20} 项"
        box = QMessageBox(self)
        box.setWindowTitle("预览缺少 ComicInfo 隔离计划")
        box.setIcon(QMessageBox.Icon.Warning)
        box.setText(f"计划 {len(plans)} 项；可执行 {len(ready)} 项；冲突 {conflicts} 项。\n不会覆盖现有目标。")
        box.setDetailedText(preview)
        box.setStandardButtons(QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel)
        box.setDefaultButton(QMessageBox.StandardButton.Cancel)
        if box.exec() != QMessageBox.StandardButton.Yes or not ready:
            return

        def action(progress, cancelled):
            result = FeatureResult()
            for index, plan in enumerate(ready, 1):
                if cancelled():
                    result.cancelled = True
                    break
                try:
                    service.execute(plan)
                    self._database.log_operation(f"ComicInfo 隔离（{plan.mode.value}）", "成功", plan.source, plan.target)
                    result.success += 1
                except Exception as error:
                    self._database.log_operation(f"ComicInfo 隔离（{plan.mode.value}）", "失败", plan.source, plan.target, str(error))
                    result.failed += 1
                progress(index, len(ready), plan.source.name)
            result.skipped = conflicts
            return result

        self.cancel_button.setEnabled(True)
        self.run_worker(action, "正在隔离缺少 ComicInfo 项…", self._isolated, allow_pause=True)

    def _isolated(self, result: FeatureResult) -> None:
        state = "隔离已取消" if result.cancelled else "隔离完成"
        self.task.status.setText(f"{state} · 成功 {result.success} · 失败 {result.failed} · 冲突跳过 {result.skipped}")
        QMessageBox.information(self, "缺少 ComicInfo 隔离", self.task.status.text() + "\n若使用移动模式，请重新扫描漫画库。")

    def organize_cbz_files(self) -> None:
        if self._thread is not None:
            return
        raw_output = self.output.text().strip()
        if not raw_output:
            QMessageBox.warning(self, "CBZ 同名目录整理", "请先选择包含 CBZ 的输出目录。")
            return
        root = Path(raw_output)
        mode = IsolationMode(str(self.organize_mode.currentData()))
        try:
            plans = CbzOrganizeService().build_plans(root, mode)
        except OSError as error:
            QMessageBox.critical(self, "CBZ 同名目录整理", str(error))
            return
        ready = [plan for plan in plans if plan.status is PlanStatus.READY]
        conflicts = len(plans) - len(ready)
        if not plans:
            QMessageBox.information(self, "CBZ 同名目录整理", "所选目录根层没有 CBZ 文件。")
            return
        preview = "\n".join(f"{plan.mode.value}：{plan.source} → {plan.target}" for plan in plans[:20])
        if len(plans) > 20:
            preview += f"\n……另有 {len(plans) - 20} 项"
        box = QMessageBox(self)
        box.setWindowTitle("预览 CBZ 同名目录整理计划")
        box.setIcon(QMessageBox.Icon.Warning)
        box.setText(f"计划 {len(plans)} 项；可执行 {len(ready)} 项；冲突 {conflicts} 项。不会覆盖目标。")
        box.setDetailedText(preview)
        box.setStandardButtons(QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.Cancel)
        box.setDefaultButton(QMessageBox.StandardButton.Cancel)
        if box.exec() != QMessageBox.StandardButton.Yes or not ready:
            return

        def action(progress, cancelled):
            result = FeatureResult()
            service = CbzOrganizeService()
            for index, plan in enumerate(ready, 1):
                if cancelled():
                    result.cancelled = True
                    break
                try:
                    service.execute(plan)
                    self._database.log_operation(f"CBZ 同名目录整理（{mode.value}）", "成功", plan.source, plan.target)
                    result.success += 1
                except Exception as error:
                    self._database.log_operation(f"CBZ 同名目录整理（{mode.value}）", "失败", plan.source, plan.target, str(error))
                    result.failed += 1
                progress(index, len(ready), plan.source.name)
            result.skipped = conflicts
            return result

        self.cancel_button.setEnabled(True)
        self.run_worker(action, "正在整理 CBZ 到同名目录…", self._organized, allow_pause=True)

    def _organized(self, result: FeatureResult) -> None:
        state = "整理已取消" if result.cancelled else "整理完成"
        self.task.status.setText(f"{state} · 成功 {result.success} · 失败 {result.failed} · 冲突跳过 {result.skipped}")
        QMessageBox.information(self, "CBZ 同名目录整理", self.task.status.text())

    def _thread_finished(self) -> None:
        super()._thread_finished(); self.pack_button.setEnabled(True); self.pause_button.setEnabled(False); self.pause_button.setText("暂停"); self.cancel_button.setEnabled(False)
