from __future__ import annotations

from PySide6.QtCore import QAbstractItemModel
from PySide6.QtWidgets import QFrame, QHBoxLayout, QLabel, QLineEdit, QPushButton, QWidget


class FilterBar(QFrame):
    def __init__(self, placeholder: str = "搜索文件夹名或 ID…") -> None:
        super().__init__()
        self.setObjectName("FilterBar")
        self._bound_model: QAbstractItemModel | None = None
        self.layout = QHBoxLayout(self)
        self.layout.setContentsMargins(12, 10, 12, 10)
        self.layout.setSpacing(8)
        self.search = QLineEdit()
        self.search.setPlaceholderText(placeholder)
        self.search.setClearButtonEnabled(True)
        self.search.setMinimumWidth(260)
        self.layout.addWidget(self.search, 1)
        self.result_count = QLabel("")
        self.result_count.setObjectName("ResultCount")
        self.result_count.setVisible(False)
        self.layout.addWidget(self.result_count)
        self.reset_button = QPushButton("重置")
        self.reset_button.setObjectName("CompactButton")
        self.reset_button.setToolTip("清除搜索条件")
        self.reset_button.setVisible(False)
        self.reset_button.clicked.connect(self.search.clear)
        self.search.textChanged.connect(lambda text: self.reset_button.setVisible(bool(text)))
        self.layout.addWidget(self.reset_button)

    def add_control(self, widget: QWidget) -> None:
        self.layout.addWidget(widget)

    def set_result_count(self, count: int, total: int | None = None) -> None:
        text = f"{count} 项" if total is None or total == count else f"{count} / {total} 项"
        self.result_count.setText(text)
        self.result_count.setVisible(True)

    def reset(self) -> None:
        self.search.clear()

    def bind_model(self, model: QAbstractItemModel) -> None:
        """Keep the visible/total result summary in sync with a table model."""
        self._bound_model = model
        for signal in (model.modelReset, model.rowsInserted, model.rowsRemoved, model.layoutChanged):
            signal.connect(self._sync_result_count)
        self._sync_result_count()

    def _sync_result_count(self, *_args: object) -> None:
        if self._bound_model is None:
            return
        visible = self._bound_model.rowCount()
        source_model = getattr(self._bound_model, "sourceModel", lambda: None)()
        total = source_model.rowCount() if source_model is not None else visible
        self.set_result_count(visible, total)
