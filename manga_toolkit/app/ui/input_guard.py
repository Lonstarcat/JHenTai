from __future__ import annotations

from PySide6.QtCore import QEvent, QObject
from PySide6.QtWidgets import QAbstractSpinBox, QComboBox


class AccidentalWheelGuard(QObject):
    """Prevent wheel scrolling from silently changing form values."""

    def eventFilter(self, watched: QObject, event: QEvent) -> bool:
        if event.type() == QEvent.Type.Wheel and isinstance(watched, (QAbstractSpinBox, QComboBox)):
            event.ignore()
            return True
        return super().eventFilter(watched, event)
