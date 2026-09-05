from __future__ import annotations

from dataclasses import dataclass

from PySide6.QtCore import QSize, Signal
from PySide6.QtWidgets import (
    QApplication,
    QFrame,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QStyle,
    QVBoxLayout,
)

from app.ui.components.status_badge import StatusBadge


@dataclass(frozen=True, slots=True)
class NavigationItem:
    label: str
    icon: QStyle.StandardPixmap


class Sidebar(QFrame):
    current_changed = Signal(int)

    def __init__(self, items: tuple[NavigationItem, ...]) -> None:
        super().__init__()
        self.setObjectName("Sidebar")
        self.setFixedWidth(232)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(12, 18, 12, 14)
        brand = QLabel("Manga Library Toolkit")
        brand.setObjectName("BrandTitle")
        subtitle = QLabel("Library maintenance")
        subtitle.setObjectName("BrandSubtitle")
        layout.addWidget(brand)
        layout.addWidget(subtitle)
        layout.addSpacing(18)
        self.navigation = QListWidget()
        self.navigation.setObjectName("Navigation")
        self.navigation.setIconSize(QSize(18, 18))
        self.navigation.setSpacing(1)
        style = QApplication.style()
        for item in items:
            list_item = QListWidgetItem(style.standardIcon(item.icon), item.label)
            list_item.setSizeHint(QSize(0, 42))
            self.navigation.addItem(list_item)
        self.navigation.currentRowChanged.connect(self.current_changed)
        layout.addWidget(self.navigation, 1)
        safety = StatusBadge("安全模式", "success")
        layout.addWidget(safety)

    def set_current_index(self, index: int) -> None:
        self.navigation.setCurrentRow(index)
