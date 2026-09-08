from __future__ import annotations

from PySide6.QtCore import QLineF, QPointF, QRectF, Qt
from PySide6.QtGui import QColor, QIcon, QPainter, QPainterPath, QPen, QPixmap


_THEME_COLORS = {
    "light": ("#667085", "#315CC8"),
    "dark": ("#AEB4BE", "#B9C8FF"),
    "monochrome": ("#222222", "#FFFFFF"),
}


def navigation_icon(name: str, theme: str = "light") -> QIcon:
    normal, selected = _THEME_COLORS.get(theme, _THEME_COLORS["light"])
    icon = QIcon()
    icon.addPixmap(_draw(name, QColor(normal)), QIcon.Mode.Normal, QIcon.State.Off)
    icon.addPixmap(_draw(name, QColor(selected)), QIcon.Mode.Selected, QIcon.State.Off)
    return icon


def menu_icon(theme: str = "light") -> QIcon:
    return navigation_icon("menu", theme)


def _draw(name: str, color: QColor) -> QPixmap:
    pixmap = QPixmap(48, 48)
    pixmap.setDevicePixelRatio(2.0)
    pixmap.fill(Qt.GlobalColor.transparent)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    pen = QPen(color, 1.8, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin)
    painter.setPen(pen)
    painter.setBrush(Qt.BrushStyle.NoBrush)

    if name == "dashboard":
        for rect in (QRectF(4, 4, 6, 6), QRectF(14, 4, 6, 6), QRectF(4, 14, 6, 6), QRectF(14, 14, 6, 6)):
            painter.drawRoundedRect(rect, 1.4, 1.4)
    elif name == "tasks":
        painter.drawEllipse(QRectF(3.5, 5, 5, 5))
        painter.drawEllipse(QRectF(3.5, 14, 5, 5))
        painter.drawLines((QLineF(11, 7.5, 20, 7.5), QLineF(11, 16.5, 20, 16.5)))
        painter.drawLines((QLineF(5, 7.5, 6.2, 8.7), QLineF(6.2, 8.7, 8, 6.3)))
    elif name == "scan":
        folder = QPainterPath(QPointF(3, 7))
        folder.lineTo(9, 7); folder.lineTo(11, 9); folder.lineTo(20, 9); folder.lineTo(20, 18); folder.lineTo(3, 18); folder.closeSubpath()
        painter.drawPath(folder)
        painter.drawEllipse(QRectF(13, 12, 5, 5)); painter.drawLine(QLineF(17, 16, 20, 19))
    elif name == "status":
        painter.drawEllipse(QRectF(3.5, 3.5, 17, 17))
        painter.drawArc(QRectF(7, 3.5, 10, 17), 90 * 16, 180 * 16)
        painter.drawArc(QRectF(7, 3.5, 10, 17), -90 * 16, 180 * 16)
        painter.drawLine(QLineF(4, 12, 20, 12))
    elif name == "duplicate":
        painter.drawRoundedRect(QRectF(4, 4, 11, 13), 1.5, 1.5)
        painter.drawRoundedRect(QRectF(9, 7, 11, 13), 1.5, 1.5)
    elif name == "unicode":
        painter.drawText(QRectF(2, 2, 12, 17), Qt.AlignmentFlag.AlignCenter, "A")
        painter.drawText(QRectF(10, 6, 12, 16), Qt.AlignmentFlag.AlignCenter, "文")
    elif name == "rename":
        tag = QPainterPath(QPointF(4, 5))
        tag.lineTo(13, 5); tag.lineTo(20, 12); tag.lineTo(12, 20); tag.lineTo(4, 12); tag.closeSubpath()
        painter.drawPath(tag); painter.drawEllipse(QRectF(7, 8, 2, 2))
    elif name == "metadata":
        page = QPainterPath(QPointF(5, 3))
        page.lineTo(15, 3); page.lineTo(20, 8); page.lineTo(20, 21); page.lineTo(5, 21); page.closeSubpath()
        painter.drawPath(page); painter.drawLine(QLineF(15, 3, 15, 8)); painter.drawLine(QLineF(15, 8, 20, 8))
        painter.drawLines((QLineF(9, 12, 16, 12), QLineF(9, 16, 16, 16)))
    elif name == "directory":
        painter.drawRoundedRect(QRectF(3, 7, 18, 12), 1.5, 1.5)
        painter.drawLine(QLineF(4, 7, 9, 7)); painter.drawLine(QLineF(9, 7, 11, 9))
        painter.drawLines((QLineF(9, 14, 11.5, 16.5), QLineF(11.5, 16.5, 16, 12)))
    elif name == "compare":
        painter.drawLine(QLineF(4, 8, 19, 8)); painter.drawLines((QLineF(16, 5, 19, 8), QLineF(19, 8, 16, 11)))
        painter.drawLine(QLineF(20, 16, 5, 16)); painter.drawLines((QLineF(8, 13, 5, 16), QLineF(5, 16, 8, 19)))
    elif name == "cbz":
        painter.drawRoundedRect(QRectF(4, 5, 16, 15), 1.5, 1.5)
        painter.drawLine(QLineF(4, 9, 20, 9)); painter.drawLine(QLineF(12, 5, 12, 15))
        painter.drawLines((QLineF(10, 15, 14, 15), QLineF(10, 18, 14, 18)))
    elif name == "settings":
        for y, knob in ((6, 9), (12, 16), (18, 7)):
            painter.drawLine(QLineF(4, y, 20, y)); painter.drawEllipse(QRectF(knob - 1.5, y - 1.5, 3, 3))
    elif name == "menu":
        painter.drawLines((QLineF(5, 7, 19, 7), QLineF(5, 12, 19, 12), QLineF(5, 17, 19, 17)))
    else:
        painter.drawEllipse(QRectF(5, 5, 14, 14))

    painter.end()
    return pixmap
