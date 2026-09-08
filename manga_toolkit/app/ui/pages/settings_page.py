from __future__ import annotations

from collections.abc import Callable
from pathlib import Path

from PySide6.QtCore import QSize, QThread, Signal
from PySide6.QtWidgets import (
    QComboBox,
    QDialog,
    QFileDialog,
    QFormLayout,
    QFrame,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMessageBox,
    QPushButton,
    QScrollArea,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from app.models.gallery_status import GallerySite
from app.services.credential_service import CredentialService, CredentialStorageError
from app.services.settings_service import AppSettings, SettingsService
from app.services.tool_detection_service import ToolInfo
from app.ui.components import PageHeader, StatusBadge
from app.ui.widgets.numeric_inputs import NoWheelDoubleSpinBox, NoWheelSpinBox
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
        self._loading_values = True
        self._build_ui()
        self._load_values()
        self._connect_dirty_signals()
        self._loading_values = False
        self.save_button.setVisible(False)
        self.detect_tools()

    def _build_ui(self) -> None:
        self.setObjectName("PageRoot")
        outer_layout = QVBoxLayout(self)
        outer_layout.setContentsMargins(28, 26, 28, 26)
        outer_layout.setSpacing(14)
        self.detect_button = QPushButton("检测外部工具")
        self.detect_button.clicked.connect(self.detect_tools)
        self.save_feedback = QLabel("")
        self.save_feedback.setObjectName("SecondaryText")
        self.save_feedback.setVisible(False)
        self.save_button = QPushButton("保存设置")
        self.save_button.clicked.connect(self.save)
        header = PageHeader("设置", "管理漫画库、外部工具和网络凭据")
        header.add_action(self.save_feedback)
        header.add_action(self.save_button, primary=True)
        outer_layout.addWidget(header)

        general_group = QGroupBox("常规")
        general_group.setObjectName("SettingsGroup")
        general_form = QFormLayout(general_group)
        self.library_edit = QLineEdit()
        general_form.addRow("漫画库路径", self._path_row(self.library_edit, self._choose_library))

        tools_group = QGroupBox("外部工具")
        tools_group.setObjectName("SettingsGroup")
        tools_form = QFormLayout(tools_group)
        for name in ("7-Zip", "FFmpeg", "FFprobe", "Czkawka"):
            edit = QLineEdit()
            status = StatusBadge("未检测", "neutral")
            self._tool_edits[name] = edit
            self._tool_status[name] = status
            tools_form.addRow(name, self._tool_row(name, edit, status))

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

        self.batch_size = NoWheelSpinBox()
        self.batch_size.setRange(1, 25)
        status_form.addRow("每批数量（项）", self.batch_size)
        self.request_interval = NoWheelDoubleSpinBox()
        self.request_interval.setRange(0.0, 60.0)
        self.request_interval.setSingleStep(0.5)
        status_form.addRow("请求间隔（秒）", self.request_interval)
        self.pause_every = NoWheelSpinBox()
        self.pause_every.setRange(1, 20)
        status_form.addRow("连续批次数（批）", self.pause_every)
        self.pause_seconds = NoWheelDoubleSpinBox()
        self.pause_seconds.setRange(0.0, 120.0)
        status_form.addRow("批次暂停（秒）", self.pause_seconds)
        self.retries = NoWheelSpinBox()
        self.retries.setRange(0, 5)
        status_form.addRow("失败重试（次）", self.retries)

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

        settings_shell = QFrame()
        settings_shell.setObjectName("SettingsShell")
        shell_layout = QHBoxLayout(settings_shell)
        shell_layout.setContentsMargins(0, 0, 0, 0)
        shell_layout.setSpacing(14)
        self.category_list = QListWidget()
        self.category_list.setObjectName("SettingsNavigation")
        self.category_list.setFixedWidth(176)
        self.category_list.setSpacing(2)
        for label in ("常规", "外部工具", "画廊与网络"):
            item = QListWidgetItem(label)
            item.setSizeHint(QSize(0, 42))
            self.category_list.addItem(item)
        self.category_stack = QStackedWidget()
        self.category_stack.setObjectName("SettingsStack")
        self.category_stack.addWidget(self._category_page(general_group))
        self.category_stack.addWidget(self._category_page(tools_group, self.detect_button))
        self.category_stack.addWidget(self._category_page(
            status_group,
            description="请求限制用于降低对远程站点的压力；连续批次达到设定值后会按批次暂停秒数等待。",
        ))
        self.category_list.currentRowChanged.connect(self.category_stack.setCurrentIndex)
        self.category_list.setCurrentRow(0)
        shell_layout.addWidget(self.category_list)
        shell_layout.addWidget(self.category_stack, 1)
        outer_layout.addWidget(settings_shell, 1)

    @staticmethod
    def _category_page(
        group: QGroupBox,
        action: QPushButton | None = None,
        description: str = "",
    ) -> QScrollArea:
        scroll = QScrollArea()
        scroll.setObjectName("SettingsScroll")
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QScrollArea.Shape.NoFrame)
        content = QWidget()
        content.setObjectName("SettingsContent")
        layout = QVBoxLayout(content)
        layout.setContentsMargins(0, 0, 4, 0)
        layout.setSpacing(12)
        if description:
            hint = QLabel(description)
            hint.setObjectName("SettingsHint")
            hint.setWordWrap(True)
            layout.addWidget(hint)
        if action is not None:
            action_row = QHBoxLayout()
            action_row.addStretch(1)
            action_row.addWidget(action)
            layout.addLayout(action_row)
        layout.addWidget(group)
        layout.addStretch(1)
        scroll.setWidget(content)
        return scroll

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
        self._tool_edits["Czkawka"].setText(self._settings.czkawka_path)
        site_index = self.gallery_site.findData(self._settings.gallery_site)
        self.gallery_site.setCurrentIndex(max(0, site_index))
        cache_index = self.cache_hours.findData(self._settings.status_cache_hours)
        self.cache_hours.setCurrentIndex(max(0, cache_index))
        self.batch_size.setValue(self._settings.status_batch_size)
        self.request_interval.setValue(self._settings.status_request_interval)
        self.pause_every.setValue(self._settings.status_pause_every_batches)
        self.pause_seconds.setValue(self._settings.status_pause_seconds)
        self.retries.setValue(self._settings.status_retries)
        self._refresh_credential_state()

    def _connect_dirty_signals(self) -> None:
        self.library_edit.textChanged.connect(self._mark_dirty)
        for edit in self._tool_edits.values():
            edit.textChanged.connect(self._mark_dirty)
        for edit in self.cookie_edits.values():
            edit.textChanged.connect(self._mark_dirty)
        for combo in (self.gallery_site, self.cache_hours):
            combo.currentIndexChanged.connect(self._mark_dirty)
        for control in (
            self.batch_size,
            self.request_interval,
            self.pause_every,
            self.pause_seconds,
            self.retries,
        ):
            control.valueChanged.connect(self._mark_dirty)

    def _mark_dirty(self, *_args: object) -> None:
        if self._loading_values:
            return
        self.save_button.setVisible(True)
        self.save_feedback.setText("有未保存更改")
        self.save_feedback.setVisible(True)

    def _refresh_credential_state(self) -> None:
        previous_loading = self._loading_values
        self._loading_values = True
        try:
            state = self._credentials.state()
            values = (state.ipb_member_id, state.ipb_pass_hash, state.igneous)
            for name, stored in zip(CredentialService.COOKIE_NAMES, values, strict=True):
                self.cookie_edits[name].clear()
                self.cookie_edits[name].setPlaceholderText("已安全保存（留空保持）" if stored else "未设置")
        except CredentialStorageError:
            for edit in self.cookie_edits.values():
                edit.setPlaceholderText("凭据存储不可用")
        finally:
            self._loading_values = previous_loading

    def _choose_library(self) -> None:
        selected = QFileDialog.getExistingDirectory(
            self,
            "选择漫画库",
            self.library_edit.text() or str(Path.home()),
        )
        if selected:
            self.library_edit.setText(selected)

    def set_library_path(self, value: str) -> None:
        self._loading_values = True
        self.library_edit.setText(value)
        self._settings.library_path = value
        self._loading_values = False

    def set_global_modes(self, safety_mode: bool, theme_mode: str) -> None:
        self._settings.safety_mode = safety_mode
        self._settings.theme_mode = theme_mode

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
        try:
            existing_cookies = self._credentials.get_cookies()
        except CredentialStorageError as error:
            QMessageBox.critical(self, "凭据读取失败", str(error))
            return
        dialog = WebLoginDialog(site, existing_cookies, self)
        if dialog.exec() != QDialog.DialogCode.Accepted:
            return
        try:
            for name, value in dialog.captured_cookies.items():
                self._credentials.set_cookie(name, value)
            self._refresh_credential_state()
        except CredentialStorageError as error:
            QMessageBox.critical(self, "凭据保存失败", str(error))
            return
        if dialog.browser_verified:
            QMessageBox.information(self, "登录状态", f"登录状态可用：{dialog.verification_message}")
        else:
            self.test_login()

    def clear_cookies(self) -> None:
        previous_loading = self._loading_values
        self._loading_values = True
        try:
            for name in CredentialService.COOKIE_NAMES:
                self._credentials.delete_cookie(name)
                self.cookie_edits[name].clear()
                self.cookie_edits[name].setPlaceholderText("未设置")
        except CredentialStorageError as error:
            QMessageBox.critical(self, "清除失败", str(error))
        finally:
            self._loading_values = previous_loading

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
        validation_error = self._validate_values()
        if validation_error:
            self.save_feedback.setText(f"保存失败：{validation_error}")
            self.save_feedback.setVisible(True)
            self.save_button.setVisible(True)
            QMessageBox.warning(self, "设置参数错误", validation_error)
            return
        settings = AppSettings(
            library_path=self.library_edit.text().strip(),
            seven_zip_path=self._tool_edits["7-Zip"].text().strip(),
            ffmpeg_path=self._tool_edits["FFmpeg"].text().strip(),
            ffprobe_path=self._tool_edits["FFprobe"].text().strip(),
            czkawka_path=self._tool_edits["Czkawka"].text().strip(),
            safety_mode=self._settings.safety_mode,
            gallery_site=str(self.gallery_site.currentData()),
            status_batch_size=self.batch_size.value(),
            status_request_interval=self.request_interval.value(),
            status_pause_every_batches=self.pause_every.value(),
            status_pause_seconds=self.pause_seconds.value(),
            status_retries=self.retries.value(),
            status_cache_hours=int(self.cache_hours.currentData()),
            theme_mode=self._settings.theme_mode,
        )
        try:
            self._save_entered_cookies()
            self._settings_service.save(settings)
        except (OSError, CredentialStorageError) as error:
            self.save_feedback.setText(f"保存失败：{error}")
            self.save_feedback.setVisible(True)
            QMessageBox.critical(self, "保存失败", str(error))
            return
        self._settings = settings
        self.settings_saved.emit(settings)
        self.save_feedback.setText("保存成功")
        self.save_feedback.setVisible(True)
        self.save_button.setVisible(False)

    def _validate_values(self) -> str | None:
        library = self.library_edit.text().strip()
        if not library:
            return "漫画库路径不能为空。"
        if not Path(library).is_dir():
            return f"漫画库路径不存在或无法访问：{library}"
        for name, edit in self._tool_edits.items():
            value = edit.text().strip()
            if value and not Path(value).is_file():
                return f"{name} 路径不是有效文件：{value}"
        member_id = self.cookie_edits["ipb_member_id"].text().strip()
        if member_id and not member_id.isdecimal():
            return "ipb_member_id 只能填写数字。"
        pass_hash = self.cookie_edits["ipb_pass_hash"].text().strip()
        if pass_hash and len(pass_hash) < 8:
            return "ipb_pass_hash 长度异常，请重新复制完整 Cookie。"
        igneous = self.cookie_edits["igneous"].text().strip()
        if igneous and any(character.isspace() for character in igneous):
            return "igneous 不能包含空格或换行。"
        if not 1 <= self.batch_size.value() <= 25:
            return "每批数量必须为 1～25。"
        if self.request_interval.value() < 0:
            return "请求间隔不能为负数。"
        if self.pause_seconds.value() < 0:
            return "批次暂停不能为负数。"
        return None

    def _save_entered_cookies(self) -> None:
        for name, edit in self.cookie_edits.items():
            value = edit.text().strip()
            if value:
                self._credentials.set_cookie(name, value)
                edit.clear()
                edit.setPlaceholderText("已安全保存（留空保持）")
