from __future__ import annotations

from dataclasses import dataclass
from PySide6.QtCore import QAbstractAnimation, QEasingCurve, QPropertyAnimation, QRect, QSize, Signal, Qt
from PySide6.QtGui import QIcon, QPixmap
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
from app.ui.navigation_icons import navigation_icon


@dataclass(frozen=True, slots=True)
class NavigationItem:
    label: str
    icon: str | QStyle.StandardPixmap


class Sidebar(QFrame):
    current_changed = Signal(int)

    def __init__(self, items: tuple[NavigationItem, ...]) -> None:
        super().__init__()
        self.setObjectName("Sidebar")
        self._items = items
        self._compact = False
        self._theme = "light"
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
        self.navigation.setUniformItemSizes(True)
        style = QApplication.style()
        for item in items:
            icon = navigation_icon(item.icon, self._theme) if isinstance(item.icon, str) else style.standardIcon(item.icon)
            list_item = QListWidgetItem(icon, item.label)
            list_item.setToolTip(item.label)
            list_item.setSizeHint(QSize(0, 42))
            list_item.setTextAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter)
            self.navigation.addItem(list_item)
        self._indicator = QFrame(self.navigation.viewport())
        self._indicator.setObjectName("NavigationIndicator")
        self._indicator.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents)
        self._indicator.hide()
        self._indicator_animation = QPropertyAnimation(self._indicator, b"geometry", self)
        self._indicator_animation.setDuration(160)
        self._indicator_animation.setEasingCurve(QEasingCurve.Type.OutCubic)
        self._indicator_initialized = False
        self.navigation.currentRowChanged.connect(self._move_indicator)
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
            row.setTextAlignment(
                Qt.AlignmentFlag.AlignCenter
                if compact
                else Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter
            )
        self.navigation.setProperty("compact", compact)
        self.navigation.viewport().update()
        style = self.style()
        style.unpolish(self)
        style.polish(self)

    def set_theme(self, theme: str) -> None:
        self._theme = theme if theme in {"light", "dark", "monochrome"} else "light"
        style = QApplication.style()
        for index, item in enumerate(self._items):
            icon = navigation_icon(item.icon, self._theme) if isinstance(item.icon, str) else style.standardIcon(item.icon)
            self.navigation.item(index).setIcon(icon)
        self.navigation.viewport().update()

    def _move_indicator(self, row: int) -> None:
        item = self.navigation.item(row)
        if item is None:
            self._indicator.hide()
            return
        rect = self.navigation.visualItemRect(item)
        target = QRect(2, rect.center().y() - 11, 3, 22)
        self._indicator.show()
        self._indicator.raise_()
        if not self._indicator_initialized or not self.isVisible():
            self._indicator.setGeometry(target)
            self._indicator_initialized = True
            return
        if self._indicator_animation.state() is QAbstractAnimation.State.Running:
            self._indicator_animation.stop()
        self._indicator_animation.setStartValue(self._indicator.geometry())
        self._indicator_animation.setEndValue(target)
        self._indicator_animation.start(QAbstractAnimation.DeletionPolicy.KeepWhenStopped)
