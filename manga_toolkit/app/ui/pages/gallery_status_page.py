from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

from PySide6.QtCore import QThread, QTimer, QUrl, Signal, Qt
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import (
    QApplication,
    QAbstractItemView,
    QCheckBox,
    QComboBox,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QMessageBox,
    QPushButton,
    QSplitter,
    QStackedWidget,
    QTableView,
    QVBoxLayout,
    QWidget,
)

from app.models.gallery_status import (
    ERROR_STATUSES,
    GalleryMetadataSnapshot,
    GalleryReference,
    GallerySite,
    GalleryStatus,
    GalleryStatusRecord,
)
from app.services.credential_service import CredentialService
from app.services.database_service import DatabaseService
from app.services.gallery_status_service import StatusCheckMode, StatusCheckOptions
from app.services.settings_service import SettingsService
from app.ui.components import (
    BadgeDelegate,
    DetailPanel,
    EmptyState,
    FilterBar,
    PageHeader,
    StatCard,
    TaskProgress,
)
from app.ui.gallery_status_table_model import GalleryStatusFilterModel, GalleryStatusTableModel
from app.workers.gallery_status_worker import GalleryStatusWorker
from app.workers.report_worker import GalleryStatusReportWorker


class GalleryStatusPage(QWidget):
    task_state_changed = Signal(str)
    status_counts_changed = Signal(int)

    FILTERS: tuple[tuple[str, GalleryStatus | None], ...] = (
        ("全部状态", None),
        ("当前最新", GalleryStatus.LATEST),
        ("发现新版本", GalleryStatus.UPDATE_AVAILABLE),
        ("已 Expunge", GalleryStatus.EXPUNGED),
        ("已替换", GalleryStatus.REPLACED),
        ("已移除", GalleryStatus.REMOVED),
        ("版权下架", GalleryStatus.COPYRIGHT_REMOVED),
        ("已删除", GalleryStatus.DELETED),
        ("Token 错误", GalleryStatus.TOKEN_INVALID),
        ("网络错误", GalleryStatus.NETWORK_ERROR),
        ("请求受限", GalleryStatus.RATE_LIMITED),
        ("未知", GalleryStatus.UNKNOWN),
    )

    MODES: tuple[tuple[str, StatusCheckMode], ...] = (
        ("检查全部（使用有效缓存）", StatusCheckMode.ALL),
        ("只检查从未检查", StatusCheckMode.NEVER_CHECKED),
        ("只检查超过缓存时间", StatusCheckMode.EXPIRED),
        ("只检查异常", StatusCheckMode.ERRORS),
        ("只检查存在新版本", StatusCheckMode.UPDATES),
    )

    def __init__(
        self,
        database: DatabaseService,
        settings_service: SettingsService,
        credentials: CredentialService,
    ) -> None:
        super().__init__()
        self.setObjectName("PageRoot")
        self._database = database
        self._settings_service = settings_service
        self._credentials = credentials
        configured_root = settings_service.load().library_path
        self._library_root_value = Path(configured_root) if configured_root else None
        self._thread: QThread | None = None
        self._worker: GalleryStatusWorker | None = None
        self._report_thread: QThread | None = None
        self._report_worker: GalleryStatusReportWorker | None = None
        self._model = GalleryStatusTableModel()
        self._proxy = GalleryStatusFilterModel()
        self._proxy.setSourceModel(self._model)
        self._build_ui()
        QTimer.singleShot(0, self.load_cache)

    @property
    def is_running(self) -> bool:
        return self._thread is not None or self._report_thread is not None

    def _build_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(28, 26, 28, 26)
        layout.setSpacing(14)

        self.check_all_button = QPushButton("检查全部")
        self.check_all_button.clicked.connect(self.check_all)
        self.check_selected_button = QPushButton("检查选中")
        self.check_selected_button.clicked.connect(self.check_selected)
        self.export_button = QPushButton("导出 Excel")
        self.export_button.clicked.connect(self.export_excel)
        header = PageHeader("画廊状态", "检查本地画廊有效性、版本变化和远程可访问状态")
        header.add_action(self.check_selected_button)
        header.add_action(self.export_button)
        header.add_action(self.check_all_button, primary=True)
        layout.addWidget(header)

        cards = QHBoxLayout()
        cards.setSpacing(12)
        self.latest_card = StatCard("当前最新")
        self.update_card = StatCard("有新版本")
        self.deleted_card = StatCard("已删除")
        self.copyright_card = StatCard("版权下架")
        self.failed_card = StatCard("检查失败")
        for card in (
            self.latest_card,
            self.update_card,
            self.deleted_card,
            self.copyright_card,
            self.failed_card,
        ):
            cards.addWidget(card, 1)
        layout.addLayout(cards)

        filters = FilterBar("搜索标题、文件夹或 GID…")
        filters.search.textChanged.connect(self._proxy.set_search)
        self.filter_combo = QComboBox()
        for label, status in self.FILTERS:
            self.filter_combo.addItem(label, status)
        self.filter_combo.currentIndexChanged.connect(self._change_filter)
        self.mode_combo = QComboBox()
        for label, mode in self.MODES:
            self.mode_combo.addItem(label, mode)
        self.force_refresh = QCheckBox("强制刷新")
        filters.add_control(self.filter_combo)
        filters.add_control(self.mode_combo)
        filters.add_control(self.force_refresh)
        layout.addWidget(filters)

        actions = QFrame()
        actions.setObjectName("Panel")
        action_row = QHBoxLayout(actions)
        action_row.setContentsMargins(12, 8, 12, 8)
        open_button = QPushButton("打开最新画廊")
        open_button.clicked.connect(self.open_latest)
        copy_url_button = QPushButton("复制 URL")
        copy_url_button.clicked.connect(self.copy_latest_url)
        copy_gid_button = QPushButton("复制 GID")
        copy_gid_button.clicked.connect(self.copy_latest_gid)
        compare_button = QPushButton("版本比较")
        compare_button.clicked.connect(self.view_comparison)
        self.refresh_errors_button = QPushButton("刷新异常")
        self.refresh_errors_button.clicked.connect(self.refresh_errors)
        self.stop_button = QPushButton("停止")
        self.stop_button.setProperty("variant", "danger")
        self.stop_button.setEnabled(False)
        self.stop_button.clicked.connect(self.stop)
        for button in (
            open_button,
            copy_url_button,
            copy_gid_button,
            compare_button,
            self.refresh_errors_button,
        ):
            action_row.addWidget(button)
        action_row.addStretch(1)
        action_row.addWidget(self.stop_button)
        layout.addWidget(actions)

        self.task_progress = TaskProgress(
            "远程状态检查",
            "默认只分析，不会删除、移动或替换本地漫画",
        )
        layout.addWidget(self.task_progress)

        self.result_stack = QStackedWidget()
        self.empty_state = EmptyState(
            "暂无画廊状态记录",
            "请先完成库扫描，然后运行画廊状态检查。",
            "检查全部",
        )
        self.empty_state.action.clicked.connect(self.check_all)
        self.result_stack.addWidget(self.empty_state)
        splitter = QSplitter()
        self.table = QTableView()
        self.table.setModel(self._proxy)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SelectionMode.ExtendedSelection)
        self.table.setAlternatingRowColors(True)
        self.table.setSortingEnabled(True)
        self.table.setWordWrap(False)
        self.table.setShowGrid(False)
        self.table.verticalHeader().setVisible(False)
        self.table.verticalHeader().setDefaultSectionSize(42)
        self.table.setItemDelegate(BadgeDelegate({0, 2}))
        self.table.setColumnWidth(0, 150)
        self.table.setColumnWidth(1, 90)
        self.table.setColumnWidth(2, 90)
        self.table.setColumnWidth(3, 320)
        self.table.setColumnWidth(12, 300)
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

    def load_cache(self) -> None:
        if self._thread is not None:
            return
        root = self._library_root(show_error=False)
        if root is not None:
            self._start_worker(root, StatusCheckMode.ALL, cache_only=True, clear=True)

    def set_library_root(self, value: str, reload_cache: bool = True) -> None:
        self._library_root_value = Path(value) if value else None
        if reload_cache and self._thread is None and self._report_thread is None:
            self.load_cache()

    def check_all(self) -> None:
        root = self._library_root()
        if root is None:
            return
        mode = self.mode_combo.currentData()
        self._start_worker(
            root,
            mode if isinstance(mode, StatusCheckMode) else StatusCheckMode.ALL,
            force_refresh=self.force_refresh.isChecked(),
            clear=True,
        )

    def check_selected(self) -> None:
        records = self._selected_records()
        if not records:
            QMessageBox.information(self, "画廊状态", "请先在表格中选择至少一项。")
            return
        root = self._library_root()
        if root is not None:
            self._start_worker(
                root,
                StatusCheckMode.ALL,
                force_refresh=True,
                selected_references=[record.reference for record in records],
                clear=False,
            )

    def refresh_errors(self) -> None:
        root = self._library_root()
        if root is not None:
            self._start_worker(root, StatusCheckMode.ERRORS, clear=True)

    def stop(self) -> None:
        if self._worker is not None:
            self._worker.request_cancel()
            self.stop_button.setEnabled(False)
            self.task_progress.status.setText("正在停止；当前请求完成后结束…")

    def export_excel(self) -> None:
        records = self._model.records()
        if not records:
            QMessageBox.information(self, "导出报告", "当前没有可导出的检查结果。")
            return
        destination, _ = QFileDialog.getSaveFileName(
            self,
            "导出画廊状态报告",
            "画廊状态检查报告.xlsx",
            "Excel 工作簿 (*.xlsx)",
        )
        if not destination:
            return
        if not destination.casefold().endswith(".xlsx"):
            destination += ".xlsx"
        self._start_report(records, Path(destination))

    def open_latest(self) -> None:
        record = self._first_selected_record()
        if record and record.latest_url:
            QDesktopServices.openUrl(QUrl(record.latest_url))

    def copy_latest_url(self) -> None:
        record = self._first_selected_record()
        if record and record.latest_url:
            QApplication.clipboard().setText(record.latest_url)
            self.task_progress.status.setText("已复制最新画廊 URL")

    def copy_latest_gid(self) -> None:
        record = self._first_selected_record()
        if record and record.current_gid is not None:
            QApplication.clipboard().setText(str(record.current_gid))
            self.task_progress.status.setText("已复制最新 GID")

    def view_comparison(self) -> None:
        record = self._first_selected_record()
        if record is None:
            QMessageBox.information(self, "版本比较", "请先选择一条画廊记录。")
            return
        local = record.local_metadata
        current = record.current_metadata
        if local is None or current is None:
            QMessageBox.information(self, "版本比较", "该记录没有可比较的当前/最新 metadata。")
            return

        def format_snapshot(label: str, metadata: GalleryMetadataSnapshot) -> list[str]:
            try:
                posted = (
                    datetime.fromtimestamp(metadata.posted, UTC).astimezone().strftime("%Y-%m-%d %H:%M:%S")
                    if metadata.posted is not None
                    else "—"
                )
            except (OSError, OverflowError, ValueError):
                posted = str(metadata.posted)
            return [
                label,
                f"GID：{metadata.gid}",
                f"标题：{metadata.title or '—'}",
                f"日文标题：{metadata.title_jpn or '—'}",
                f"页数：{metadata.filecount if metadata.filecount is not None else '—'}",
                f"大小：{GalleryStatusTableModel._format_size(metadata.filesize)}",
                f"发布时间：{posted}",
                f"分类：{metadata.category or '—'}",
                f"标签：{', '.join(metadata.tags) if metadata.tags else '—'}",
            ]

        lines = format_snapshot("当前版本", local)
        lines.extend(("", *format_snapshot("最新版本", current)))
        lines.extend(
            (
                "",
                f"页数变化：{record.page_delta if record.page_delta is not None else '—'}",
                f"大小变化：{GalleryStatusTableModel._format_size(record.size_delta)}",
            )
        )
        dialog = QMessageBox(self)
        dialog.setWindowTitle("当前版本 vs 最新版本")
        dialog.setIcon(QMessageBox.Icon.Information)
        dialog.setTextFormat(Qt.TextFormat.PlainText)
        dialog.setText("\n".join(lines))
        dialog.exec()

    def _start_worker(
        self,
        root: Path,
        mode: StatusCheckMode,
        force_refresh: bool = False,
        selected_references: list[GalleryReference] | None = None,
        cache_only: bool = False,
        clear: bool = True,
    ) -> None:
        if self._thread is not None:
            return
        if clear:
            self._model.clear()
            self.result_stack.setCurrentIndex(0)
            self._update_cards()
        settings = self._settings_service.load()
        options = StatusCheckOptions(
            site=GallerySite(settings.gallery_site),
            batch_size=settings.status_batch_size,
            request_interval=settings.status_request_interval,
            pause_every_batches=settings.status_pause_every_batches,
            pause_seconds=settings.status_pause_seconds,
            retries=settings.status_retries,
            cache_hours=settings.status_cache_hours,
        )
        thread = QThread(self)
        worker = GalleryStatusWorker(
            root,
            self._database,
            self._credentials,
            options,
            mode,
            force_refresh=force_refresh,
            selected_references=selected_references,
            cache_only=cache_only,
        )
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.progress.connect(self._on_progress)
        worker.batch_ready.connect(self._on_batch_ready)
        worker.completed.connect(self._on_completed)
        worker.failed.connect(self._on_failed)
        worker.finished.connect(thread.quit)
        worker.finished.connect(worker.deleteLater)
        thread.finished.connect(self._on_thread_finished)
        thread.finished.connect(thread.deleteLater)
        self._thread = thread
        self._worker = worker
        self._set_checking(True)
        thread.start()

    def _start_report(self, records: list[GalleryStatusRecord], destination: Path) -> None:
        if self._report_thread is not None:
            return
        thread = QThread(self)
        worker = GalleryStatusReportWorker(records, destination)
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.succeeded.connect(lambda path: QMessageBox.information(self, "导出完成", path))
        worker.failed.connect(lambda error: QMessageBox.critical(self, "导出失败", error))
        worker.finished.connect(thread.quit)
        worker.finished.connect(worker.deleteLater)
        thread.finished.connect(self._on_report_finished)
        thread.finished.connect(thread.deleteLater)
        self._report_thread = thread
        self._report_worker = worker
        self.export_button.setEnabled(False)
        self.task_progress.status.setText("正在后台生成 Excel 报告…")
        thread.start()

    def _on_batch_ready(self, records: list[GalleryStatusRecord]) -> None:
        self._model.upsert_batch(records)
        if records:
            self.result_stack.setCurrentIndex(1)
        self._update_cards()

    def _update_cards(self) -> None:
        records = self._model.records()
        counts = {status: 0 for status in GalleryStatus}
        for record in records:
            counts[record.status] += 1
        self.latest_card.set_value(counts[GalleryStatus.LATEST])
        updates = counts[GalleryStatus.UPDATE_AVAILABLE]
        self.update_card.set_value(updates)
        self.deleted_card.set_value(counts[GalleryStatus.DELETED])
        self.copyright_card.set_value(counts[GalleryStatus.COPYRIGHT_REMOVED])
        self.failed_card.set_value(sum(counts[status] for status in ERROR_STATUSES))
        self.status_counts_changed.emit(updates)

    def _on_progress(self, current: int, total: int, message: str) -> None:
        self.task_progress.update_progress(current, total, f"{current} / {total} · {message}")

    def _on_completed(self, total: int, cache_hits: int, cancelled: bool) -> None:
        prefix = "检查已停止" if cancelled else "检查完成"
        self.task_progress.status.setText(f"{prefix} · 结果 {total} · 缓存命中 {cache_hits}")
        self.task_progress.progress.setValue(self.task_progress.progress.maximum())

    def _on_failed(self, message: str) -> None:
        self.task_progress.status.setText("画廊状态检查失败")
        QMessageBox.critical(self, "画廊状态检查失败", message)

    def _on_report_finished(self) -> None:
        self._report_thread = None
        self._report_worker = None
        self.export_button.setEnabled(True)

    def _on_thread_finished(self) -> None:
        self._thread = None
        self._worker = None
        self._set_checking(False)

    def _set_checking(self, active: bool) -> None:
        self.check_all_button.setEnabled(not active)
        self.check_selected_button.setEnabled(not active)
        self.refresh_errors_button.setEnabled(not active)
        self.stop_button.setEnabled(active)
        self.task_state_changed.emit("正在检查画廊状态…" if active else "空闲")

    def _change_filter(self, _index: int = 0) -> None:
        status = self.filter_combo.currentData()
        self._proxy.set_status_filter(status if isinstance(status, GalleryStatus) else None)

    def _show_details(self, proxy_index, _previous) -> None:
        if not proxy_index.isValid():
            return
        source_index = self._proxy.mapToSource(proxy_index)
        record = self._model.record_at(source_index.row())
        self.detail.set_details(
            record.reference.local_title,
            [
                ("状态", record.status.label),
                ("来源", record.reference.source),
                ("本地 GID", str(record.local_gid or "—")),
                ("最新 GID", str(record.current_gid or "—")),
                ("本地页数", str(record.local_metadata.filecount if record.local_metadata and record.local_metadata.filecount is not None else "—")),
                ("最新页数", str(record.current_metadata.filecount if record.current_metadata and record.current_metadata.filecount is not None else "—")),
                ("页数变化", str(record.page_delta if record.page_delta is not None else "—")),
                ("最新 URL", record.latest_url or "—"),
                ("最后检查", record.checked_at.astimezone().strftime("%Y-%m-%d %H:%M:%S")),
                ("备注", record.note or record.error or "—"),
                ("本地路径", str(record.reference.folder_path)),
            ],
        )

    def _library_root(self, show_error: bool = True) -> Path | None:
        if self._library_root_value is None:
            if show_error:
                QMessageBox.warning(self, "画廊状态", "请先在设置中选择漫画库并完成库扫描。")
            return None
        return self._library_root_value

    def _selected_records(self) -> list[GalleryStatusRecord]:
        selection = self.table.selectionModel()
        if selection is None:
            return []
        records: list[GalleryStatusRecord] = []
        seen: set[int] = set()
        for proxy_index in selection.selectedRows():
            source_index = self._proxy.mapToSource(proxy_index)
            if source_index.row() not in seen:
                seen.add(source_index.row())
                records.append(self._model.record_at(source_index.row()))
        return records

    def _first_selected_record(self) -> GalleryStatusRecord | None:
        records = self._selected_records()
        return records[0] if records else None
