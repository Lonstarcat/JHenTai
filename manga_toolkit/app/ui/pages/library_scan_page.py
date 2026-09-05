from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QThread, Signal
from PySide6.QtWidgets import (
    QAbstractItemView,
    QComboBox,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QSplitter,
    QStackedWidget,
    QTableView,
    QVBoxLayout,
    QWidget,
)

from app.models.gallery_folder import GalleryFolder, GalleryType
from app.services.database_service import DatabaseService
from app.ui.components import (
    BadgeDelegate,
    DetailPanel,
    EmptyState,
    FilterBar,
    PageHeader,
    StatusBadge,
    TaskProgress,
)
from app.ui.gallery_table_model import GalleryFilterModel, GalleryTableModel
from app.workers.scan_worker import ScanWorker


class LibraryScanPage(QWidget):
    scan_started = Signal(str)
    scan_summary = Signal(int, int, int, int, int)
    scan_finished = Signal(str, bool)

    def __init__(self, database: DatabaseService, initial_path: str = "") -> None:
        super().__init__()
        self.setObjectName("PageRoot")
        self._database = database
        self._thread: QThread | None = None
        self._worker: ScanWorker | None = None
        self._normal_count = 0
        self._archive_count = 0
        self._missing_comic_info = 0
        self._active_root: Path | None = None
        self._model = GalleryTableModel()
        self._proxy = GalleryFilterModel()
        self._proxy.setSourceModel(self._model)
        self._build_ui(initial_path)

    def _build_ui(self, initial_path: str) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(28, 26, 28, 26)
        layout.setSpacing(14)

        self.start_button = QPushButton("扫描漫画库")
        self.start_button.clicked.connect(self.start_scan)
        browse_button = QPushButton("选择目录")
        browse_button.clicked.connect(self.choose_directory)
        header = PageHeader("漫画库", "扫描和查看漫画文件夹及根目录 CBZ；扫描过程不会修改任何文件")
        header.add_action(browse_button)
        header.add_action(self.start_button, primary=True)
        layout.addWidget(header)

        path_panel = QFrame()
        path_panel.setObjectName("Panel")
        path_layout = QHBoxLayout(path_panel)
        path_layout.setContentsMargins(14, 12, 14, 12)
        path_layout.addWidget(QLabel("漫画库路径"))
        self.path_edit = QLineEdit(initial_path)
        self.path_edit.setPlaceholderText(r"例如 Z:\JH 或 \\NAS\Manga")
        path_layout.addWidget(self.path_edit, 1)
        self.cancel_button = QPushButton("取消扫描")
        self.cancel_button.setProperty("variant", "danger")
        self.cancel_button.setEnabled(False)
        self.cancel_button.clicked.connect(self.cancel_scan)
        path_layout.addWidget(self.cancel_button)
        layout.addWidget(path_panel)

        steps = QHBoxLayout()
        self.step_scan = StatusBadge("1 扫描", "info")
        self.step_analyze = StatusBadge("2 分析", "neutral")
        self.step_preview = StatusBadge("3 预览", "neutral")
        self.step_execute = StatusBadge("4 执行（未启用）", "neutral")
        for badge in (self.step_scan, self.step_analyze, self.step_preview, self.step_execute):
            steps.addWidget(badge)
        steps.addStretch(1)
        layout.addLayout(steps)

        self.task_progress = TaskProgress("库扫描", "等待扫描")
        layout.addWidget(self.task_progress)

        filters = FilterBar()
        filters.search.textChanged.connect(self._proxy.set_search)
        type_combo = QComboBox()
        type_combo.addItems(("全部类型", "Normal", "Archive", "Unknown"))
        type_combo.currentTextChanged.connect(self._proxy.set_gallery_type)
        unicode_combo = QComboBox()
        unicode_combo.addItems(("全部编码", "NFC", "NFD", "OTHER"))
        unicode_combo.currentTextChanged.connect(self._proxy.set_unicode)
        storage_combo = QComboBox()
        storage_combo.addItems(("全部载体", "Folder", "CBZ"))
        storage_combo.currentTextChanged.connect(self._proxy.set_storage)
        filters.add_control(type_combo)
        filters.add_control(unicode_combo)
        filters.add_control(storage_combo)
        layout.addWidget(filters)

        self.result_stack = QStackedWidget()
        self.empty_state = EmptyState(
            "尚未扫描漫画库",
            "选择本地磁盘、映射盘或 UNC 漫画库，扫描一级文件夹与根目录 CBZ。",
            "选择目录",
        )
        self.empty_state.action.clicked.connect(self.choose_directory)
        self.result_stack.addWidget(self.empty_state)

        splitter = QSplitter()
        self.table = QTableView()
        self.table.setModel(self._proxy)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.table.setAlternatingRowColors(True)
        self.table.setSortingEnabled(True)
        self.table.setWordWrap(False)
        self.table.setShowGrid(False)
        self.table.verticalHeader().setVisible(False)
        self.table.verticalHeader().setDefaultSectionSize(42)
        self.table.horizontalHeader().setStretchLastSection(True)
        self.table.setItemDelegate(BadgeDelegate({1, 2, 5, 8, 9, 10}))
        self.table.setColumnWidth(0, 90)
        self.table.setColumnWidth(1, 90)
        self.table.setColumnWidth(2, 75)
        self.table.setColumnWidth(3, 340)
        self.table.setColumnWidth(4, 420)
        self.detail = DetailPanel()
        splitter.addWidget(self.table)
        splitter.addWidget(self.detail)
        splitter.setStretchFactor(0, 1)
        splitter.setStretchFactor(1, 0)
        self.result_stack.addWidget(splitter)
        layout.addWidget(self.result_stack, 1)
        selection = self.table.selectionModel()
        if selection is not None:
            selection.currentRowChanged.connect(self._show_details)

    def set_library_path(self, value: str) -> None:
        if self._thread is None:
            self.path_edit.setText(value)

    @property
    def is_scanning(self) -> bool:
        return self._thread is not None

    def choose_directory(self) -> None:
        selected = QFileDialog.getExistingDirectory(
            self,
            "选择漫画库",
            self.path_edit.text() or str(Path.home()),
        )
        if selected:
            self.path_edit.setText(selected)

    def start_scan(self) -> None:
        if self._thread is not None:
            return
        raw_path = self.path_edit.text().strip()
        if not raw_path:
            QMessageBox.warning(self, "库扫描", "请先选择漫画库路径。")
            return

        root = Path(raw_path)
        self._active_root = root
        self._model.clear()
        self._normal_count = 0
        self._archive_count = 0
        self._missing_comic_info = 0
        self.result_stack.setCurrentIndex(0)
        self.task_progress.update_progress(0, 1, "正在准备扫描…")
        self.step_scan.set_status("info")
        self.step_analyze.set_status("neutral")
        self.step_preview.set_status("neutral")
        self.start_button.setEnabled(False)
        self.cancel_button.setEnabled(True)
        self.scan_started.emit(str(root))

        thread = QThread(self)
        worker = ScanWorker(root, self._database)
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.progress.connect(self._on_progress)
        worker.batch_ready.connect(self._on_batch)
        worker.completed.connect(self._on_completed)
        worker.failed.connect(self._on_failed)
        worker.finished.connect(thread.quit)
        worker.finished.connect(worker.deleteLater)
        thread.finished.connect(self._on_thread_finished)
        thread.finished.connect(thread.deleteLater)
        self._thread = thread
        self._worker = worker
        thread.start()

    def cancel_scan(self) -> None:
        if self._worker is not None:
            self._worker.request_cancel()
            self.cancel_button.setEnabled(False)
            self.task_progress.status.setText("正在安全停止扫描…")

    def _on_progress(self, current: int, total: int, name: str) -> None:
        self.task_progress.update_progress(current, total, f"{current} / {total} · {name}")

    def _on_batch(self, galleries: list[GalleryFolder]) -> None:
        self._model.append_batch(galleries)
        self._normal_count += sum(g.gallery_type == GalleryType.NORMAL for g in galleries)
        self._archive_count += sum(g.gallery_type == GalleryType.ARCHIVE for g in galleries)
        self._missing_comic_info += sum(not g.has_comic_info for g in galleries)
        if galleries:
            self.result_stack.setCurrentIndex(1)
            self.step_analyze.set_status("info")

    def _on_completed(self, total: int, issues: int, cached: int, cancelled: bool) -> None:
        if cancelled:
            text = f"扫描已取消 · 已读取 {total} 个漫画项目 · 未写入本次缓存"
            self.step_scan.set_status("warning")
        else:
            text = f"扫描完成 · {total} 个漫画 · 异常 {issues} · 复用缓存 {cached}"
            self.task_progress.progress.setValue(self.task_progress.progress.maximum())
            self.step_scan.set_status("success")
            self.step_analyze.set_status("success")
            self.step_preview.set_status("success")
        self.task_progress.status.setText(text)
        self.scan_summary.emit(
            total,
            self._normal_count,
            self._archive_count,
            issues,
            self._missing_comic_info,
        )
        if self._active_root is not None:
            self.scan_finished.emit(str(self._active_root), not cancelled)

    def _on_failed(self, message: str) -> None:
        self.task_progress.status.setText("扫描失败")
        self.step_scan.set_status("error")
        QMessageBox.critical(self, "扫描失败", message)

    def _show_details(self, proxy_index, _previous) -> None:
        if not proxy_index.isValid():
            return
        source_index = self._proxy.mapToSource(proxy_index)
        gallery = self._model.item_at(source_index.row())
        metadata = "metadata + ametadata" if gallery.has_metadata and gallery.has_ametadata else "metadata" if gallery.has_metadata else "ametadata" if gallery.has_ametadata else "缺失"
        self.detail.set_details(
            gallery.folder_name,
            [
                ("ID", gallery.gallery_id or "—"),
                ("类型", gallery.gallery_type.value),
                ("载体", gallery.storage_type.value),
                ("Unicode", gallery.unicode_status.value),
                ("Metadata", metadata),
                ("ComicInfo", "存在" if gallery.has_comic_info else "缺失"),
                ("文件数", str(gallery.file_count)),
                ("大小", GalleryTableModel._format_size(gallery.folder_size)),
                ("路径", str(gallery.path)),
            ],
        )

    def _on_thread_finished(self) -> None:
        self._thread = None
        self._worker = None
        self.start_button.setEnabled(True)
        self.cancel_button.setEnabled(False)
        self._active_root = None
