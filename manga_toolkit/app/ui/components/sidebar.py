from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PySide6.QtCore import QSize, Signal, Qt
from PySide6.QtGui import QPixmap
from PySide6.QtWidgets import (
    QApplication,
    QFrame,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QStyle,
    QVBoxLayout,
)

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
        brand_row = QHBoxLayout()
        logo = QLabel()
        logo_path = Path(__file__).resolve().parents[3] / "Emangato.png"
        if logo_path.is_file():
            logo.setPixmap(
                QPixmap(str(logo_path)).scaled(
                    38,
                    38,
                    Qt.AspectRatioMode.KeepAspectRatio,
                    Qt.TransformationMode.SmoothTransformation,
                )
            )
        brand = QLabel("Emangato")
        brand.setObjectName("BrandTitle")
        subtitle = QLabel("Library maintenance")
        subtitle.setObjectName("BrandSubtitle")
        brand_text = QVBoxLayout()
        brand_text.setSpacing(1)
        brand_text.addWidget(brand)
        brand_text.addWidget(subtitle)
        brand_row.addWidget(logo)
        brand_row.addLayout(brand_text, 1)
        layout.addLayout(brand_row)
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

    def set_current_index(self, index: int) -> None:
        self.navigation.setCurrentRow(index)
