from __future__ import annotations

from PySide6.QtCore import QModelIndex, QRectF, Qt
from PySide6.QtGui import QColor, QPainter, QPalette
from PySide6.QtWidgets import QApplication, QStyle, QStyleOptionViewItem, QStyledItemDelegate


class BadgeDelegate(QStyledItemDelegate):
    def __init__(self, columns: set[int]) -> None:
        super().__init__()
        self._columns = columns

    def paint(self, painter: QPainter, option: QStyleOptionViewItem, index: QModelIndex) -> None:
        if index.column() not in self._columns:
            super().paint(painter, option, index)
            return
        text = str(index.data(Qt.ItemDataRole.DisplayRole) or "—")
        base_option = QStyleOptionViewItem(option)
        self.initStyleOption(base_option, index)
        base_option.text = ""
        style = option.widget.style() if option.widget else QApplication.style()
        style.drawControl(QStyle.ControlElement.CE_ItemViewItem, base_option, painter, option.widget)

        dark = option.palette.color(QPalette.ColorRole.Window).lightness() < 128
        application = QApplication.instance()
        monochrome = bool(application and application.property("theme") == "monochrome")
        background, foreground = self._colors(text, dark, monochrome)
        metrics = option.fontMetrics
        width = min(option.rect.width() - 16, metrics.horizontalAdvance(text) + 20)
        badge = QRectF(
            option.rect.x() + 8,
            option.rect.center().y() - 11,
            max(36, width),
            22,
        )
        painter.save()
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(background)
        painter.drawRoundedRect(badge, 6, 6)
        painter.setPen(foreground)
        painter.drawText(badge, Qt.AlignmentFlag.AlignCenter, text)
        painter.restore()

    @staticmethod
    def _colors(text: str, dark: bool, monochrome: bool = False) -> tuple[QColor, QColor]:
        if monochrome:
            return QColor("#E4E4E4"), QColor("#000000")
        normalized = text.casefold()
        success = {"当前最新", "正常", "完整", "nfc", "是", "已安装"}
        info = {"存在新版本", "旧版本", "有更新", "处理中", "archive"}
        warning = {
            "已 expunge", "已被其他画廊替换", "nfd", "other", "需要确认", "名称不同",
            "token 错误", "访问被拒绝", "请求受限", "网络错误",
            "normal ↔ archive", "unicode 重复", "short",
        }
        error = {"已移除 / 不可用", "版权下架", "已删除", "缺失", "否", "损坏", "私有画廊"}
        if normalized in {item.casefold() for item in success}:
            return (QColor("#153B2D"), QColor("#79D9AC")) if dark else (QColor("#E5F6EE"), QColor("#16794F"))
        if normalized in {item.casefold() for item in info}:
            return (QColor("#1D3158"), QColor("#9AB5FF")) if dark else (QColor("#E8F0FE"), QColor("#285EBD"))
        if normalized in {item.casefold() for item in warning}:
            return (QColor("#49351A"), QColor("#F4BD64")) if dark else (QColor("#FFF2D8"), QColor("#A15C05"))
        if normalized in {item.casefold() for item in error}:
            return (QColor("#482525"), QColor("#FF9C96")) if dark else (QColor("#FDE8E7"), QColor("#B42318"))
        return (QColor("#2A2F35"), QColor("#B3B8C0")) if dark else (QColor("#EEF0F2"), QColor("#5B6472"))
