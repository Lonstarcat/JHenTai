from __future__ import annotations

from collections.abc import Callable
from pathlib import Path

from PySide6.QtCore import QThread, Signal
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDoubleSpinBox,
    QDialog,
    QFileDialog,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QScrollArea,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from app.models.gallery_status import GallerySite
from app.services.credential_service import CredentialService, CredentialStorageError
from app.services.settings_service import AppSettings, SettingsService
from app.services.tool_detection_service import ToolInfo
from app.ui.components import PageHeader, StatusBadge
from app.workers.tool_detection_worker import ToolDetectionWorker
from app.workers.login_test_worker import LoginTestWorker


class SettingsPage(QWidget):
    settings_saved = Signal(object)

    def __init__(self, settings_service: SettingsService, credentials: CredentialService) -> None:
        super().__init__()
        self._settings_service = settings_service
        self._credentials = credentials
        self._settings = settings_service.load()
        self._tool_edits: dict[str, QLineEdit] = {}
        self._tool_status: dict[str, QLabel] = {}
        self._detect_thread: QThread | None = None
        self._detect_worker: ToolDetectionWorker | None = None
        self._login_thread: QThread | None = None
        self._login_worker: LoginTestWorker | None = None
        self._build_ui()
        self._load_values()
        self.detect_tools()

    def _build_ui(self) -> None:
        self.setObjectName("PageRoot")
        outer_layout = QVBoxLayout(self)
        outer_layout.setContentsMargins(0, 0, 0, 0)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        content = QWidget()
        layout = QVBoxLayout(content)
        layout.setContentsMargins(28, 26, 28, 26)
        layout.setSpacing(14)
        self.detect_button = QPushButton("检测外部工具")
        self.detect_button.clicked.connect(self.detect_tools)
        save_button = QPushButton("保存设置")
        save_button.clicked.connect(self.save)
        header = PageHeader("设置", "管理漫画库、外部工具、网络凭据、安全与外观")
        header.add_action(self.detect_button)
        header.add_action(save_button, primary=True)
        layout.addWidget(header)

        general_group = QGroupBox("常规")
        general_group.setObjectName("SettingsGroup")
        general_form = QFormLayout(general_group)
        self.library_edit = QLineEdit()
        general_form.addRow("漫画库路径", self._path_row(self.library_edit, self._choose_library))
        layout.addWidget(general_group)

        tools_group = QGroupBox("外部工具")
        tools_group.setObjectName("SettingsGroup")
        tools_form = QFormLayout(tools_group)
        for name in ("7-Zip", "FFmpeg", "FFprobe"):
            edit = QLineEdit()
            status = StatusBadge("未检测", "neutral")
            self._tool_edits[name] = edit
            self._tool_status[name] = status
            tools_form.addRow(name, self._tool_row(name, edit, status))
        layout.addWidget(tools_group)

        status_group = QGroupBox("网络与画廊状态")
        status_group.setObjectName("SettingsGroup")
        status_form = QFormLayout(status_group)
        self.gallery_site = QComboBox()
        self.gallery_site.addItem("ExHentai（优先）", GallerySite.EXHENTAI.value)
        self.gallery_site.addItem("E-Hentai", GallerySite.EHENTAI.value)
        status_form.addRow("目标站点", self.gallery_site)

        self.cache_hours = QComboBox()
        for label, hours in (("1 小时", 1), ("6 小时", 6), ("24 小时", 24), ("7 天", 168)):
            self.cache_hours.addItem(label, hours)
        status_form.addRow("缓存周期", self.cache_hours)

        self.batch_size = QSpinBox()
        self.batch_size.setRange(1, 25)
        status_form.addRow("每批数量", self.batch_size)
        self.request_interval = QDoubleSpinBox()
        self.request_interval.setRange(0.0, 60.0)
        self.request_interval.setSuffix(" 秒")
        self.request_interval.setSingleStep(0.5)
        status_form.addRow("请求间隔", self.request_interval)
        self.pause_every = QSpinBox()
        self.pause_every.setRange(1, 20)
        status_form.addRow("连续批次数", self.pause_every)
        self.pause_seconds = QDoubleSpinBox()
        self.pause_seconds.setRange(0.0, 120.0)
        self.pause_seconds.setSuffix(" 秒")
        status_form.addRow("批次暂停", self.pause_seconds)
        self.retries = QSpinBox()
        self.retries.setRange(0, 5)
        status_form.addRow("失败重试", self.retries)

        self.cookie_edits: dict[str, QLineEdit] = {}
        for name in CredentialService.COOKIE_NAMES:
            edit = QLineEdit()
            edit.setEchoMode(QLineEdit.EchoMode.Password)
            self.cookie_edits[name] = edit
            status_form.addRow(name, edit)

        credential_buttons = QHBoxLayout()
        self.login_test_button = QPushButton("测试登录状态")
        self.login_test_button.clicked.connect(self.test_login)
        web_login_button = QPushButton("网页登录 / Cloudflare 验证")
        web_login_button.clicked.connect(self.web_login)
        clear_button = QPushButton("清除已保存 Cookie")
        clear_button.clicked.connect(self.clear_cookies)
        credential_buttons.addWidget(self.login_test_button)
        credential_buttons.addWidget(web_login_button)
        credential_buttons.addWidget(clear_button)
        credential_buttons.addStretch(1)
        status_form.addRow("凭据", credential_buttons)
        layout.addWidget(status_group)

        security_group = QGroupBox("安全")
        security_group.setObjectName("SettingsGroup")
        security_form = QFormLayout(security_group)
        self.safety_mode = QCheckBox("操作前预览、禁止默认覆盖与永久删除")
        security_form.addRow("安全模式", self.safety_mode)
        layout.addWidget(security_group)

        appearance_group = QGroupBox("外观")
        appearance_group.setObjectName("SettingsGroup")
        appearance_form = QFormLayout(appearance_group)
        self.theme_mode = QComboBox()
        self.theme_mode.addItem("跟随系统", "system")
        self.theme_mode.addItem("浅色", "light")
        self.theme_mode.addItem("深色", "dark")
        self.theme_mode.addItem("黑白", "monochrome")
        appearance_form.addRow("主题", self.theme_mode)
        layout.addWidget(appearance_group)
        layout.addStretch(1)
        scroll.setWidget(content)
        outer_layout.addWidget(scroll)

    def _path_row(self, edit: QLineEdit, callback: Callable[[], None]) -> QWidget:
        widget = QWidget()
        row = QHBoxLayout(widget)
        row.setContentsMargins(0, 0, 0, 0)
        button = QPushButton("浏览…")
        button.clicked.connect(callback)
        row.addWidget(edit, 1)
        row.addWidget(button)
        return widget

    def _tool_row(self, name: str, edit: QLineEdit, status: QLabel) -> QWidget:
        widget = QWidget()
        row = QHBoxLayout(widget)
        row.setContentsMargins(0, 0, 0, 0)
        button = QPushButton("选择…")
        button.clicked.connect(lambda: self._choose_tool(name))
        row.addWidget(edit, 1)
        row.addWidget(button)
        row.addWidget(status)
        return widget

    def _load_values(self) -> None:
        self.library_edit.setText(self._settings.library_path)
        self._tool_edits["7-Zip"].setText(self._settings.seven_zip_path)
        self._tool_edits["FFmpeg"].setText(self._settings.ffmpeg_path)
        self._tool_edits["FFprobe"].setText(self._settings.ffprobe_path)
        self.safety_mode.setChecked(self._settings.safety_mode)
        site_index = self.gallery_site.findData(self._settings.gallery_site)
        self.gallery_site.setCurrentIndex(max(0, site_index))
        cache_index = self.cache_hours.findData(self._settings.status_cache_hours)
        self.cache_hours.setCurrentIndex(max(0, cache_index))
        self.batch_size.setValue(self._settings.status_batch_size)
        self.request_interval.setValue(self._settings.status_request_interval)
        self.pause_every.setValue(self._settings.status_pause_every_batches)
        self.pause_seconds.setValue(self._settings.status_pause_seconds)
        self.retries.setValue(self._settings.status_retries)
        theme_index = self.theme_mode.findData(self._settings.theme_mode)
        self.theme_mode.setCurrentIndex(max(0, theme_index))
        self._refresh_credential_state()

    def _refresh_credential_state(self) -> None:
        try:
            state = self._credentials.state()
            values = (state.ipb_member_id, state.ipb_pass_hash, state.igneous)
            for name, stored in zip(CredentialService.COOKIE_NAMES, values, strict=True):
                self.cookie_edits[name].clear()
                self.cookie_edits[name].setPlaceholderText("已安全保存（留空保持）" if stored else "未设置")
        except CredentialStorageError:
            for edit in self.cookie_edits.values():
                edit.setPlaceholderText("凭据存储不可用")

    def _choose_library(self) -> None:
        selected = QFileDialog.getExistingDirectory(
            self,
            "选择漫画库",
            self.library_edit.text() or str(Path.home()),
        )
        if selected:
            self.library_edit.setText(selected)

    def set_library_path(self, value: str) -> None:
        self.library_edit.setText(value)
        self._settings.library_path = value

    def _choose_tool(self, name: str) -> None:
        selected, _ = QFileDialog.getOpenFileName(
            self,
            f"选择 {name}",
            self._tool_edits[name].text() or str(Path.home()),
            "可执行程序 (*.exe);;所有文件 (*)",
        )
        if selected:
            self._tool_edits[name].setText(selected)
            self.detect_tools()

    def detect_tools(self) -> None:
        if self._detect_thread is not None:
            return
        configured = {name: edit.text().strip() for name, edit in self._tool_edits.items()}
        self.detect_button.setEnabled(False)
        for label in self._tool_status.values():
            if isinstance(label, StatusBadge):
                label.set_status("info", "检测中")
            else:
                label.setText("检测中…")

        thread = QThread(self)
        worker = ToolDetectionWorker(configured)
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.detected.connect(self._show_tool_results)
        worker.finished.connect(thread.quit)
        worker.finished.connect(worker.deleteLater)
        thread.finished.connect(self._finish_tool_detection)
        thread.finished.connect(thread.deleteLater)
        self._detect_thread = thread
        self._detect_worker = worker
        thread.start()

    @property
    def is_detecting_tools(self) -> bool:
        return self._detect_thread is not None

    def _show_tool_results(self, results: list[ToolInfo]) -> None:
        for info in results:
            label = self._tool_status[info.name]
            if isinstance(label, StatusBadge):
                label.set_status(
                    "success" if info.found else "warning",
                    "已找到" if info.found else "未找到",
                )
            else:
                label.setText("已安装" if info.found else "未找到")
            label.setToolTip(f"{info.path or ''}\n{info.version}\n{info.error}")

    def _finish_tool_detection(self) -> None:
        self._detect_thread = None
        self._detect_worker = None
        self.detect_button.setEnabled(True)

    @property
    def is_testing_login(self) -> bool:
        return self._login_thread is not None

    def test_login(self) -> None:
        if self._login_thread is not None:
            return
        try:
            self._save_entered_cookies()
        except CredentialStorageError as error:
            QMessageBox.critical(self, "凭据保存失败", str(error))
            return
        site = GallerySite(self.gallery_site.currentData())
        thread = QThread(self)
        worker = LoginTestWorker(self._credentials, site)
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.completed.connect(self._show_login_result)
        worker.finished.connect(thread.quit)
        worker.finished.connect(worker.deleteLater)
        thread.finished.connect(self._finish_login_test)
        thread.finished.connect(thread.deleteLater)
        self._login_thread = thread
        self._login_worker = worker
        self.login_test_button.setEnabled(False)
        self.login_test_button.setText("测试中…")
        thread.start()

    def web_login(self) -> None:
        if self._login_thread is not None:
            return
        try:
            from app.ui.web_login_dialog import WebLoginDialog
        except ImportError as error:
            QMessageBox.warning(
                self,
                "网页登录不可用",
                f"当前构建未包含 Qt WebEngine：{error}",
            )
            return
        site = GallerySite(self.gallery_site.currentData())
        dialog = WebLoginDialog(site, self)
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return
        try:
            for name, value in dialog.captured_cookies.items():
                self._credentials.set_cookie(name, value)
            self._refresh_credential_state()
        except CredentialStorageError as error:
            QMessageBox.critical(self, "凭据保存失败", str(error))
            return
        self.test_login()

    def clear_cookies(self) -> None:
        try:
            for name in CredentialService.COOKIE_NAMES:
                self._credentials.delete_cookie(name)
                self.cookie_edits[name].clear()
                self.cookie_edits[name].setPlaceholderText("未设置")
        except CredentialStorageError as error:
            QMessageBox.critical(self, "清除失败", str(error))

    def _show_login_result(self, success: bool, message: str) -> None:
        if success:
            QMessageBox.information(self, "登录状态", f"登录状态可用：{message}")
        else:
            QMessageBox.warning(self, "登录状态", f"登录状态不可用：{message}")

    def _finish_login_test(self) -> None:
        self._login_thread = None
        self._login_worker = None
        self.login_test_button.setEnabled(True)
        self.login_test_button.setText("测试登录状态")

    def save(self) -> None:
        settings = AppSettings(
            library_path=self.library_edit.text().strip(),
            seven_zip_path=self._tool_edits["7-Zip"].text().strip(),
            ffmpeg_path=self._tool_edits["FFmpeg"].text().strip(),
            ffprobe_path=self._tool_edits["FFprobe"].text().strip(),
            safety_mode=self.safety_mode.isChecked(),
            gallery_site=str(self.gallery_site.currentData()),
            status_batch_size=self.batch_size.value(),
            status_request_interval=self.request_interval.value(),
            status_pause_every_batches=self.pause_every.value(),
            status_pause_seconds=self.pause_seconds.value(),
            status_retries=self.retries.value(),
            status_cache_hours=int(self.cache_hours.currentData()),
            theme_mode=str(self.theme_mode.currentData()),
        )
        try:
            self._save_entered_cookies()
            self._settings_service.save(settings)
        except (OSError, CredentialStorageError) as error:
            QMessageBox.critical(self, "保存失败", str(error))
            return
        self._settings = settings
        self.settings_saved.emit(settings)
        QMessageBox.information(self, "设置", "设置已保存。")

    def _save_entered_cookies(self) -> None:
        for name, edit in self.cookie_edits.items():
            value = edit.text().strip()
            if value:
                self._credentials.set_cookie(name, value)
                edit.clear()
                edit.setPlaceholderText("已安全保存（留空保持）")
