from __future__ import annotations

from enum import StrEnum
from pathlib import Path

from PySide6.QtCore import QObject, Qt, Signal
from PySide6.QtGui import QFont
from PySide6.QtWidgets import QApplication


class ThemeMode(StrEnum):
    SYSTEM = "system"
    LIGHT = "light"
    DARK = "dark"
    MONOCHROME = "monochrome"


class ThemeManager(QObject):
    theme_changed = Signal(str)

    def __init__(self, application: QApplication, mode: str = ThemeMode.SYSTEM) -> None:
        super().__init__(application)
        self._application = application
        self._mode = self._parse_mode(mode)
        self._styles_dir = Path(__file__).resolve().parent / "styles"
        font = QFont()
        font.setFamilies(["Segoe UI Variable", "Segoe UI", "Microsoft YaHei UI"])
        font.setPointSize(10)
        application.setFont(font)
        style_hints = application.styleHints()
        if hasattr(style_hints, "colorSchemeChanged"):
            style_hints.colorSchemeChanged.connect(self._system_scheme_changed)
        self.apply()

    @property
    def mode(self) -> ThemeMode:
        return self._mode

    def set_mode(self, mode: str | ThemeMode) -> None:
        parsed = self._parse_mode(mode)
        if parsed == self._mode:
            return
        self._mode = parsed
        self.apply()

    def apply(self) -> None:
        resolved = self._resolved_mode()
        stylesheet_path = self._styles_dir / f"{resolved.value}.qss"
        try:
            stylesheet = stylesheet_path.read_text(encoding="utf-8")
        except OSError:
            stylesheet = ""
        self._application.setProperty("theme", resolved.value)
        self._application.setStyleSheet(stylesheet)
        self.theme_changed.emit(resolved.value)

    def _resolved_mode(self) -> ThemeMode:
        if self._mode is not ThemeMode.SYSTEM:
            return self._mode
        scheme = self._application.styleHints().colorScheme()
        return ThemeMode.DARK if scheme == Qt.ColorScheme.Dark else ThemeMode.LIGHT

    def _system_scheme_changed(self, _scheme: Qt.ColorScheme) -> None:
        if self._mode is ThemeMode.SYSTEM:
            self.apply()

    @staticmethod
    def _parse_mode(mode: str | ThemeMode) -> ThemeMode:
        try:
            return ThemeMode(mode)
        except ValueError:
            return ThemeMode.SYSTEM
