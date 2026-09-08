from __future__ import annotations

from dataclasses import replace
from pathlib import Path

from PySide6.QtCore import QSize, QSignalBlocker
from PySide6.QtGui import QCloseEvent, QResizeEvent
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QFrame,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from app.services.credential_service import CredentialService
from app.services.database_service import DatabaseService
from app.services.settings_service import AppSettings, SettingsService
from app.ui.components import AnimatedStackedWidget, NavigationItem, Sidebar
from app.ui.pages.dashboard_page import DashboardPage
from app.ui.pages.duplicate_detection_page import DuplicateDetectionPage
from app.ui.pages.gallery_status_page import GalleryStatusPage
from app.ui.pages.library_scan_page import LibraryScanPage
from app.ui.pages.name_organizer_page import NameOrganizerPage
from app.ui.pages.metadata_page import MetadataPage
from app.ui.pages.directory_check_page import DirectoryCheckPage
from app.ui.pages.library_compare_page import LibraryComparePage
from app.ui.pages.cbz_tools_page import CbzToolsPage
from app.ui.pages.task_history_page import TaskHistoryPage
from app.ui.pages.settings_page import SettingsPage
from app.ui.pages.unicode_tools_page import UnicodeToolsPage
from app.ui.navigation_icons import menu_icon
from app.ui.theme_manager import ThemeManager


class MainWindow(QMainWindow):
    NAVIGATION = (
        NavigationItem("仪表盘", "dashboard"),
        NavigationItem("任务状态", "tasks"),
        NavigationItem("库扫描", "scan"),
        NavigationItem("画廊状态", "status"),
        NavigationItem("重复检测", "duplicate"),
        NavigationItem("Unicode 工具", "unicode"),
        NavigationItem("名称整理", "rename"),
        NavigationItem("Metadata", "metadata"),
        NavigationItem("目录检查", "directory"),
        NavigationItem("库对比", "compare"),
        NavigationItem("CBZ 工具", "cbz"),
        NavigationItem("设置", "settings"),
    )

    def __init__(
        self,
        database: DatabaseService,
        settings_service: SettingsService,
        credentials: CredentialService,
        theme_manager: ThemeManager,
    ) -> None:
        super().__init__()
        self._database = database
        self._sidebar_user_compact = False
        self._width_class = "wide"
        self.setWindowTitle("Emangato")
        self.resize(1440, 900)
        self.setMinimumSize(960, 680)
        self._settings_service = settings_service
        self._theme_manager = theme_manager
        settings = settings_service.load()

        self.dashboard = DashboardPage()
        self.scan_page = LibraryScanPage(database, settings.library_path)
        self.status_page = GalleryStatusPage(database, settings_service, credentials)
        self.duplicate_page = DuplicateDetectionPage(database, settings_service)
        self.unicode_page = UnicodeToolsPage(database, settings_service)
        self.name_page = NameOrganizerPage(database, settings_service)
        self.metadata_page = MetadataPage(database, settings_service)
        self.directory_page = DirectoryCheckPage(database, settings_service)
        self.compare_page = LibraryComparePage(database, settings_service)
        self.cbz_page = CbzToolsPage(database, settings_service)
        self.task_page = TaskHistoryPage(database)
        self.settings_page = SettingsPage(settings_service, credentials)
        self._build_ui(settings)
        self._connect_signals()
        if settings.library_path:
            self.dashboard.update_inventory(database.list_galleries(Path(settings.library_path)))

    def _build_ui(self, settings: AppSettings) -> None:
        root = QWidget()
        root.setObjectName("AppRoot")
        self.setCentralWidget(root)
        root_layout = QVBoxLayout(root)
        root_layout.setContentsMargins(0, 0, 0, 0)
        root_layout.setSpacing(0)

        header = QFrame()
        header.setObjectName("TopBar")
        header.setFixedHeight(58)
        header_layout = QHBoxLayout(header)
        header_layout.setContentsMargins(14, 0, 20, 0)
        self.sidebar_toggle = QPushButton()
        self.sidebar_toggle.setObjectName("SidebarToggle")
        self.sidebar_toggle.setIcon(menu_icon(self._theme_manager.resolved_mode.value))
        self.sidebar_toggle.setIconSize(QSize(20, 20))
        self.sidebar_toggle.setFixedSize(36, 34)
        self.sidebar_toggle.setToolTip("折叠或展开导航")
        self.sidebar_toggle.clicked.connect(self._toggle_sidebar)
        self.page_context = QLabel("当前漫画库")
        self.page_context.setObjectName("SecondaryText")
        self.library_label = QLabel(settings.library_path or "未选择漫画库")
        self.library_label.setObjectName("PathLabel")
        self.library_label.setToolTip(settings.library_path)
        self.summary_label = QLabel("空闲")
        self.summary_label.setObjectName("SecondaryText")
        self.theme_selector = QComboBox()
        self.theme_selector.setObjectName("TopModeSelector")
        for label, value in (
            ("◐ 自动", "system"),
            ("☀ 浅色", "light"),
            ("☾ 深色", "dark"),
            ("◑ 黑白", "monochrome"),
        ):
            self.theme_selector.addItem(label, value)
        self.theme_selector.setCurrentIndex(max(0, self.theme_selector.findData(settings.theme_mode)))
        self.safe_mode_label = QLabel("安全模式")
        self.safe_mode_label.setObjectName("ModeLabel")
        self.security_switch = QCheckBox()
        self.security_switch.setObjectName("ModeSwitch")
        self.security_switch.setChecked(not settings.safety_mode)
        self.security_switch.setToolTip("关闭：安全模式；开启：高级模式")
        self.advanced_mode_label = QLabel("高级模式")
        self.advanced_mode_label.setObjectName("ModeLabel")
        header_layout.addWidget(self.sidebar_toggle)
        header_layout.addSpacing(8)
        header_layout.addWidget(self.page_context)
        header_layout.addWidget(self.library_label, 1)
        header_layout.addWidget(self.summary_label)
        header_layout.addSpacing(8)
        header_layout.addWidget(self.theme_selector)
        header_layout.addSpacing(8)
        header_layout.addWidget(self.safe_mode_label)
        header_layout.addWidget(self.security_switch)
        header_layout.addWidget(self.advanced_mode_label)
        root_layout.addWidget(header)

        body = QWidget()
        body_layout = QHBoxLayout(body)
        body_layout.setContentsMargins(0, 0, 0, 0)
        body_layout.setSpacing(0)
        self.sidebar = Sidebar(self.NAVIGATION)
        self.sidebar.set_theme(self._theme_manager.resolved_mode.value)
        self.pages = AnimatedStackedWidget()
        self.pages.setObjectName("PageStack")
        self.pages.addWidget(self.dashboard)
        self.pages.addWidget(self.task_page)
        self.pages.addWidget(self.scan_page)
        self.pages.addWidget(self.status_page)
        self.pages.addWidget(self.duplicate_page)
        self.pages.addWidget(self.unicode_page)
        for page in (self.name_page, self.metadata_page, self.directory_page, self.compare_page, self.cbz_page):
            self.pages.addWidget(page)
        self.pages.addWidget(self.settings_page)
        body_layout.addWidget(self.sidebar)
        body_layout.addWidget(self.pages, 1)
        root_layout.addWidget(body, 1)
        self.sidebar.set_current_index(0)
        self._apply_width_class(self.width())

    def _connect_signals(self) -> None:
        self.sidebar.current_changed.connect(self.pages.setCurrentIndex)
        self.security_switch.toggled.connect(self._on_security_mode_toggled)
        self.theme_selector.currentIndexChanged.connect(self._on_theme_selected)
        self._theme_manager.theme_changed.connect(self._on_theme_changed)
        self.settings_page.settings_saved.connect(self._on_settings_saved)
        self.scan_page.scan_started.connect(self._on_scan_started)
        self.scan_page.scan_summary.connect(self._on_scan_summary)
        self.scan_page.scan_finished.connect(self._on_scan_finished)
        self.status_page.task_state_changed.connect(self.summary_label.setText)
        self.status_page.status_counts_changed.connect(self.dashboard.update_gallery_counts)
        self.duplicate_page.counts_changed.connect(self.dashboard.update_duplicate_count)
        self.unicode_page.counts_changed.connect(self.dashboard.update_nfd_count)
        self.cbz_page.cbz_counts_changed.connect(self.dashboard.update_cbz_counts)
        self.duplicate_page.task_state_changed.connect(self.summary_label.setText)
        self.unicode_page.task_state_changed.connect(self.summary_label.setText)
        for page in (self.name_page, self.metadata_page, self.directory_page, self.compare_page, self.cbz_page, self.task_page):
            page.task_state_changed.connect(self.summary_label.setText)
        self.dashboard.navigate_requested.connect(self._navigate_to)

    def _navigate_to(self, label: str) -> None:
        for index, item in enumerate(self.NAVIGATION):
            if item.label == label:
                self.sidebar.set_current_index(index)
                break

    def _toggle_sidebar(self) -> None:
        if self._width_class == "compact":
            self.sidebar.setVisible(not self.sidebar.isVisible())
            return
        self._sidebar_user_compact = not self.sidebar.is_compact
        self.sidebar.set_compact(self._sidebar_user_compact)

    def resizeEvent(self, event: QResizeEvent) -> None:
        super().resizeEvent(event)
        if hasattr(self, "sidebar"):
            self._apply_width_class(event.size().width())

    def _apply_width_class(self, width: int) -> None:
        width_class = "wide" if width >= 1280 else "medium" if width >= 1050 else "compact"
        if width_class == self._width_class and width_class != "compact":
            return
        self._width_class = width_class
        if width_class != "compact":
            self.sidebar.setVisible(True)
        automatic_compact = width_class == "compact"
        self.sidebar.set_compact(automatic_compact or self._sidebar_user_compact)
        show_captions = width_class != "compact"
        self.page_context.setVisible(show_captions)
        self.summary_label.setVisible(show_captions)
        self.dashboard.set_width_class(width_class)
        margin = 28 if width_class == "wide" else 22 if width_class == "medium" else 18
        for index in range(self.pages.count()):
            page_layout = QWidget.layout(self.pages.widget(index))
            if page_layout is not None:
                page_layout.setContentsMargins(margin, 24, margin, 24)

    def _on_settings_saved(self, settings: AppSettings) -> None:
        self.library_label.setText(settings.library_path or "未选择漫画库")
        self.library_label.setToolTip(settings.library_path)
        with QSignalBlocker(self.security_switch):
            self.security_switch.setChecked(not settings.safety_mode)
        with QSignalBlocker(self.theme_selector):
            self.theme_selector.setCurrentIndex(max(0, self.theme_selector.findData(settings.theme_mode)))
        self.settings_page.set_global_modes(settings.safety_mode, settings.theme_mode)
        self._theme_manager.set_mode(settings.theme_mode)
        self.scan_page.set_library_path(settings.library_path)
        self.status_page.set_library_root(settings.library_path)
        self.duplicate_page.set_library_root(settings.library_path)
        self.unicode_page.set_library_root(settings.library_path)
        for page in (self.name_page, self.metadata_page, self.directory_page, self.compare_page, self.cbz_page):
            page.set_library_root(settings.library_path)

    def _on_security_mode_toggled(self, advanced: bool) -> None:
        previous = self._settings_service.load()
        updated = replace(previous, safety_mode=not advanced)
        try:
            self._settings_service.save(updated)
        except OSError as error:
            with QSignalBlocker(self.security_switch):
                self.security_switch.setChecked(not previous.safety_mode)
            QMessageBox.critical(self, "模式切换失败", f"无法保存安全模式：{error}")
            return
        self.settings_page.set_global_modes(updated.safety_mode, updated.theme_mode)
        self.summary_label.setText("已切换为高级模式" if advanced else "已切换为安全模式")

    def _on_theme_selected(self, _index: int) -> None:
        mode = str(self.theme_selector.currentData())
        previous = self._settings_service.load()
        updated = replace(previous, theme_mode=mode)
        try:
            self._settings_service.save(updated)
        except OSError as error:
            with QSignalBlocker(self.theme_selector):
                self.theme_selector.setCurrentIndex(max(0, self.theme_selector.findData(previous.theme_mode)))
            QMessageBox.critical(self, "主题切换失败", f"无法保存主题设置：{error}")
            return
        self._theme_manager.set_mode(mode)
        self.settings_page.set_global_modes(updated.safety_mode, mode)

    def _on_theme_changed(self, resolved_mode: str) -> None:
        self.sidebar.set_theme(resolved_mode)
        self.sidebar_toggle.setIcon(menu_icon(resolved_mode))

    def _on_scan_started(self, root: str) -> None:
        self.library_label.setText(root)
        self.library_label.setToolTip(root)
        self.summary_label.setText("正在扫描…")

    def _on_scan_summary(
        self,
        total: int,
        normal: int,
        archive: int,
        issues: int,
        missing_comic_info: int,
    ) -> None:
        self.summary_label.setText(f"漫画 {total} · 异常 {issues} · 空闲")
        self.dashboard.update_summary(total, normal, archive, issues, missing_comic_info)

    def _on_scan_finished(self, root: str, completed: bool) -> None:
        if not completed:
            return
        self.status_page.set_library_root(root)
        self.duplicate_page.set_library_root(root)
        self.unicode_page.set_library_root(root)
        for page in (self.name_page, self.metadata_page, self.directory_page, self.compare_page, self.cbz_page):
            page.set_library_root(root)
        self.dashboard.update_inventory(self._database.list_galleries(Path(root)))
        self.settings_page.set_library_path(root)
        settings = replace(self._settings_service.load(), library_path=root)
        try:
            self._settings_service.save(settings)
        except OSError:
            self.summary_label.setText("扫描完成，但漫画库路径保存失败")

    def closeEvent(self, event: QCloseEvent) -> None:
        if self.scan_page.is_scanning:
            self.scan_page.cancel_scan()
            self.summary_label.setText("正在安全停止扫描，请稍候…")
            event.ignore()
            return
        if self.settings_page.is_detecting_tools:
            self.summary_label.setText("正在完成外部工具检测，请稍候…")
            event.ignore()
            return
        if self.settings_page.is_testing_login:
            self.summary_label.setText("正在完成登录状态测试，请稍候…")
            event.ignore()
            return
        if self.status_page.is_running:
            self.status_page.stop()
            self.summary_label.setText("正在安全停止画廊状态任务，请稍候…")
            event.ignore()
            return
        if self.duplicate_page.is_running:
            self.duplicate_page.stop()
            self.summary_label.setText("正在安全停止重复检测任务，请稍候…")
            event.ignore()
            return
        if self.unicode_page.is_running:
            self.unicode_page.stop()
            self.summary_label.setText("正在安全停止 Unicode 任务，请稍候…")
            event.ignore()
            return
        for page in (self.name_page, self.metadata_page, self.directory_page, self.compare_page, self.cbz_page, self.task_page):
            if page.is_running:
                page.stop()
                self.summary_label.setText("正在安全停止后台任务，请稍候…")
                event.ignore()
                return
        super().closeEvent(event)
