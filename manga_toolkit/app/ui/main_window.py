from __future__ import annotations

from dataclasses import replace

from PySide6.QtGui import QCloseEvent
from PySide6.QtWidgets import (
    QFrame,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QPushButton,
    QStackedWidget,
    QStyle,
    QVBoxLayout,
    QWidget,
)

from app.services.credential_service import CredentialService
from app.services.database_service import DatabaseService
from app.services.settings_service import AppSettings, SettingsService
from app.ui.components import NavigationItem, Sidebar, StatusBadge
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
from app.ui.theme_manager import ThemeManager


class MainWindow(QMainWindow):
    NAVIGATION = (
        NavigationItem("仪表盘", QStyle.StandardPixmap.SP_ComputerIcon),
        NavigationItem("库扫描", QStyle.StandardPixmap.SP_DirHomeIcon),
        NavigationItem("画廊状态", QStyle.StandardPixmap.SP_BrowserReload),
        NavigationItem("重复检测", QStyle.StandardPixmap.SP_FileDialogDetailedView),
        NavigationItem("Unicode 工具", QStyle.StandardPixmap.SP_FileDialogContentsView),
        NavigationItem("名称整理", QStyle.StandardPixmap.SP_FileDialogListView),
        NavigationItem("Metadata", QStyle.StandardPixmap.SP_FileIcon),
        NavigationItem("目录检查", QStyle.StandardPixmap.SP_DialogApplyButton),
        NavigationItem("库对比", QStyle.StandardPixmap.SP_ArrowForward),
        NavigationItem("CBZ 工具", QStyle.StandardPixmap.SP_DriveHDIcon),
        NavigationItem("任务记录", QStyle.StandardPixmap.SP_MessageBoxInformation),
        NavigationItem("设置", QStyle.StandardPixmap.SP_FileDialogInfoView),
    )

    def __init__(
        self,
        database: DatabaseService,
        settings_service: SettingsService,
        credentials: CredentialService,
        theme_manager: ThemeManager,
    ) -> None:
        super().__init__()
        self.setWindowTitle("Manga Library Toolkit")
        self.resize(1440, 900)
        self.setMinimumSize(1280, 720)
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
        self.sidebar_toggle = QPushButton("☰")
        self.sidebar_toggle.setFixedSize(36, 34)
        self.sidebar_toggle.setToolTip("折叠或展开导航")
        self.sidebar_toggle.clicked.connect(self._toggle_sidebar)
        page_context = QLabel("当前漫画库")
        page_context.setObjectName("SecondaryText")
        self.library_label = QLabel(settings.library_path or "未选择漫画库")
        self.library_label.setObjectName("PathLabel")
        self.library_label.setToolTip(settings.library_path)
        self.summary_label = QLabel("空闲")
        self.summary_label.setObjectName("SecondaryText")
        self.safety_badge = StatusBadge(
            "安全模式" if settings.safety_mode else "高级模式",
            "success" if settings.safety_mode else "warning",
        )
        header_layout.addWidget(self.sidebar_toggle)
        header_layout.addSpacing(8)
        header_layout.addWidget(page_context)
        header_layout.addWidget(self.library_label, 1)
        header_layout.addWidget(self.summary_label)
        header_layout.addSpacing(8)
        header_layout.addWidget(self.safety_badge)
        root_layout.addWidget(header)

        body = QWidget()
        body_layout = QHBoxLayout(body)
        body_layout.setContentsMargins(0, 0, 0, 0)
        body_layout.setSpacing(0)
        self.sidebar = Sidebar(self.NAVIGATION)
        self.pages = QStackedWidget()
        self.pages.setObjectName("PageStack")
        self.pages.addWidget(self.dashboard)
        self.pages.addWidget(self.scan_page)
        self.pages.addWidget(self.status_page)
        self.pages.addWidget(self.duplicate_page)
        self.pages.addWidget(self.unicode_page)
        for page in (self.name_page, self.metadata_page, self.directory_page, self.compare_page, self.cbz_page, self.task_page):
            self.pages.addWidget(page)
        self.pages.addWidget(self.settings_page)
        body_layout.addWidget(self.sidebar)
        body_layout.addWidget(self.pages, 1)
        root_layout.addWidget(body, 1)
        self.sidebar.set_current_index(0)

    def _connect_signals(self) -> None:
        self.sidebar.current_changed.connect(self.pages.setCurrentIndex)
        self.settings_page.settings_saved.connect(self._on_settings_saved)
        self.scan_page.scan_started.connect(self._on_scan_started)
        self.scan_page.scan_summary.connect(self._on_scan_summary)
        self.scan_page.scan_finished.connect(self._on_scan_finished)
        self.status_page.task_state_changed.connect(self.summary_label.setText)
        self.status_page.status_counts_changed.connect(self.dashboard.update_gallery_counts)
        self.duplicate_page.counts_changed.connect(self.dashboard.update_duplicate_count)
        self.unicode_page.counts_changed.connect(self.dashboard.update_nfd_count)
        self.duplicate_page.task_state_changed.connect(self.summary_label.setText)
        self.unicode_page.task_state_changed.connect(self.summary_label.setText)
        for page in (self.name_page, self.metadata_page, self.directory_page, self.compare_page, self.cbz_page):
            page.task_state_changed.connect(self.summary_label.setText)
        self.dashboard.navigate_requested.connect(self._navigate_to)

    def _navigate_to(self, label: str) -> None:
        for index, item in enumerate(self.NAVIGATION):
            if item.label == label:
                self.sidebar.set_current_index(index)
                break

    def _toggle_sidebar(self) -> None:
        self.sidebar.setVisible(not self.sidebar.isVisible())

    def _on_settings_saved(self, settings: AppSettings) -> None:
        self.library_label.setText(settings.library_path or "未选择漫画库")
        self.library_label.setToolTip(settings.library_path)
        self.safety_badge.set_status(
            "success" if settings.safety_mode else "warning",
            "安全模式" if settings.safety_mode else "高级模式",
        )
        self._theme_manager.set_mode(settings.theme_mode)
        self.scan_page.set_library_path(settings.library_path)
        self.status_page.set_library_root(settings.library_path)
        self.duplicate_page.set_library_root(settings.library_path)
        self.unicode_page.set_library_root(settings.library_path)
        for page in (self.name_page, self.metadata_page, self.directory_page, self.compare_page, self.cbz_page):
            page.set_library_root(settings.library_path)

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
        for page in (self.name_page, self.metadata_page, self.directory_page, self.compare_page, self.cbz_page):
            if page.is_running:
                page.stop()
                self.summary_label.setText("正在安全停止后台任务，请稍候…")
                event.ignore()
                return
        super().closeEvent(event)
