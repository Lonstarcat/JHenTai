from __future__ import annotations

from PySide6.QtCore import QAbstractAnimation, QEasingCurve, QPropertyAnimation
from PySide6.QtWidgets import QGraphicsOpacityEffect, QStackedWidget, QStyle, QWidget


class AnimatedStackedWidget(QStackedWidget):
    """A restrained incoming-page fade that keeps only one animation alive."""

    def __init__(self, parent: QWidget | None = None, duration: int = 140) -> None:
        super().__init__(parent)
        self._duration = max(0, duration)
        self._animation = QPropertyAnimation(self)
        self._animation.setPropertyName(b"opacity")
        self._animation.setDuration(self._duration)
        self._animation.setEasingCurve(QEasingCurve.Type.OutCubic)
        self._animation.finished.connect(self._finish_animation)
        self._effect: QGraphicsOpacityEffect | None = None
        self._animated_widget: QWidget | None = None

    @property
    def animation_running(self) -> bool:
        return self._animation.state() == QAbstractAnimation.State.Running

    def set_animation_duration(self, duration: int) -> None:
        self._duration = max(0, duration)
        self._animation.setDuration(self._duration)

    def setCurrentIndex(self, index: int) -> None:  # noqa: N802 - Qt API compatibility
        if index == self.currentIndex():
            return
        self._stop_animation()
        super().setCurrentIndex(index)
        page = self.currentWidget()
        if page is None or not self._animations_enabled():
            return

        effect = QGraphicsOpacityEffect(page)
        effect.setOpacity(0.90)
        page.setGraphicsEffect(effect)
        self._effect = effect
        self._animated_widget = page
        self._animation.setTargetObject(effect)
        self._animation.setStartValue(0.90)
        self._animation.setEndValue(1.0)
        self._animation.start(QAbstractAnimation.DeletionPolicy.KeepWhenStopped)

    def _animations_enabled(self) -> bool:
        return self._duration > 0 and bool(
            self.style().styleHint(QStyle.StyleHint.SH_Widget_Animate, None, self)
        )

    def _stop_animation(self) -> None:
        self._animation.stop()
        if self._effect is not None:
            self._effect.setOpacity(1.0)
        if self._animated_widget is not None and self._animated_widget.graphicsEffect() is self._effect:
            self._animated_widget.setGraphicsEffect(None)
        self._animation.setTargetObject(None)
        self._effect = None
        self._animated_widget = None

    def _finish_animation(self) -> None:
        page = self._animated_widget
        effect = self._effect
        if page is None or effect is None:
            return
        effect.setOpacity(1.0)
        if page.graphicsEffect() is effect:
            page.setGraphicsEffect(None)
        self._animation.setTargetObject(None)
        self._effect = None
        self._animated_widget = None
