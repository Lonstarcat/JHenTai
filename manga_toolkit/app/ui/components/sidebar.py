from __future__ import annotations

from dataclasses import dataclass
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
    QWidget,
)

from app.core.resources import bundled_resource


@dataclass(frozen=True, slots=True)
class NavigationItem:
    label: str
    icon: QStyle.StandardPixmap


class Sidebar(QFrame):
    current_changed = Signal(int)

    def __init__(self, items: tuple[NavigationItem, ...]) -> None:
        super().__init__()
        self.setObjectName("Sidebar")
        self._items = items
        self._compact = False
        self.setFixedWidth(232)
        self._layout = QVBoxLayout(self)
        self._layout.setContentsMargins(12, 18, 12, 14)
        brand_row = QHBoxLayout()
        self.logo = QLabel()
        logo_path = bundled_resource("Emangato.png")
        if logo_path.is_file():
            self.logo.setPixmap(
                QPixmap(str(logo_path)).scaled(
                    38,
                    38,
                    Qt.AspectRatioMode.KeepAspectRatio,
                    Qt.TransformationMode.SmoothTransformation,
                )
            )
        self.brand = QLabel("Emangato")
        self.brand.setObjectName("BrandTitle")
        self.subtitle = QLabel("Library maintenance")
        self.subtitle.setObjectName("BrandSubtitle")
        self.brand_text = QWidget()
        brand_text_layout = QVBoxLayout(self.brand_text)
        brand_text_layout.setContentsMargins(0, 0, 0, 0)
        brand_text_layout.setSpacing(1)
        brand_text_layout.addWidget(self.brand)
        brand_text_layout.addWidget(self.subtitle)
        brand_row.addWidget(self.logo)
        brand_row.addWidget(self.brand_text, 1)
        self._layout.addLayout(brand_row)
        self._layout.addSpacing(18)
        self.navigation = QListWidget()
        self.navigation.setObjectName("Navigation")
        self.navigation.setIconSize(QSize(18, 18))
        self.navigation.setSpacing(1)
        style = QApplication.style()
        for item in items:
            list_item = QListWidgetItem(style.standardIcon(item.icon), item.label)
            list_item.setToolTip(item.label)
            list_item.setSizeHint(QSize(0, 42))
            self.navigation.addItem(list_item)
        self.navigation.currentRowChanged.connect(self.current_changed)
        self._layout.addWidget(self.navigation, 1)

    def set_current_index(self, index: int) -> None:
        self.navigation.setCurrentRow(index)

    @property
    def is_compact(self) -> bool:
        return self._compact

    def set_compact(self, compact: bool) -> None:
        """Collapse labels without changing navigation rows or their indexes."""
        if compact == self._compact:
            return
        self._compact = compact
        self.setProperty("compact", compact)
        self.setFixedWidth(76 if compact else 232)
        self._layout.setContentsMargins(9 if compact else 12, 18, 9 if compact else 12, 14)
        self.brand_text.setVisible(not compact)
        for index, item in enumerate(self._items):
            row = self.navigation.item(index)
            row.setText("" if compact else item.label)
            row.setTextAlignment(Qt.AlignmentFlag.AlignCenter if compact else Qt.AlignmentFlag.AlignLeft)
        style = self.style()
        style.unpolish(self)
        style.polish(self)
