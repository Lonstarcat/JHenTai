from __future__ import annotations

from PySide6.QtCore import QUrl
from PySide6.QtNetwork import QNetworkCookie
from PySide6.QtWebEngineCore import QWebEnginePage, QWebEngineProfile
from PySide6.QtWebEngineWidgets import QWebEngineView
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from app.models.gallery_status import GallerySite


class WebLoginDialog(QDialog):
    """Off-the-record browser that captures only the three EH session cookies."""

    LOGIN_URL = "https://forums.e-hentai.org/index.php?act=Login&CODE=00"
    EX_URL = "https://exhentai.org/"
    ALLOWED_COOKIES = {"ipb_member_id", "ipb_pass_hash", "igneous"}

    def __init__(self, site: GallerySite, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._site = site
        self._captured: dict[str, str] = {}
        self.setWindowTitle("E-Hentai 网页登录")
        self.resize(1000, 760)
        self.setMinimumSize(800, 600)

        layout = QVBoxLayout(self)
        hint = QLabel(
            "在下方页面完成论坛登录和 Cloudflare 验证。程序只捕获登录 Cookie，"
            "不会读取或保存账号密码；浏览器会话关闭后清除。"
        )
        hint.setWordWrap(True)
        layout.addWidget(hint)

        controls = QHBoxLayout()
        forum_button = QPushButton("打开论坛登录")
        forum_button.clicked.connect(lambda: self._view.setUrl(QUrl(self.LOGIN_URL)))
        ex_button = QPushButton("访问 ExHentai 获取 igneous")
        ex_button.clicked.connect(lambda: self._view.setUrl(QUrl(self.EX_URL)))
        controls.addWidget(forum_button)
        controls.addWidget(ex_button)
        controls.addStretch(1)
        self._status = QLabel("尚未捕获登录 Cookie")
        controls.addWidget(self._status)
        layout.addLayout(controls)

        # An unnamed profile is off-the-record. Explicitly disable persistent
        # cookies so browser session data is never written beside app.db.
        self._profile = QWebEngineProfile(self)
        self._profile.setPersistentCookiesPolicy(
            QWebEngineProfile.PersistentCookiesPolicy.NoPersistentCookies
        )
        self._profile.cookieStore().cookieAdded.connect(self._on_cookie_added)
        self._view = QWebEngineView(self)
        self._view.setPage(QWebEnginePage(self._profile, self._view))
        self._view.setUrl(QUrl(self.LOGIN_URL))
        layout.addWidget(self._view, 1)

        self._buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Cancel)
        self._save_button = self._buttons.addButton(
            "保存捕获的 Cookie 并测试",
            QDialogButtonBox.ButtonRole.AcceptRole,
        )
        self._save_button.setEnabled(False)
        self._buttons.accepted.connect(self._accept_cookies)
        self._buttons.rejected.connect(self.reject)
        layout.addWidget(self._buttons)

    @property
    def captured_cookies(self) -> dict[str, str]:
        return dict(self._captured)

    def _on_cookie_added(self, cookie: QNetworkCookie) -> None:
        try:
            name = bytes(cookie.name()).decode("ascii")
            value = bytes(cookie.value()).decode("utf-8")
        except (UnicodeDecodeError, ValueError):
            return
        if name not in self.ALLOWED_COOKIES or not value:
            return
        self._captured[name] = value
        present = [name for name in ("ipb_member_id", "ipb_pass_hash", "igneous") if name in self._captured]
        self._status.setText("已捕获：" + "、".join(present))
        required = {"ipb_member_id", "ipb_pass_hash"}
        if self._site is GallerySite.EXHENTAI:
            required.add("igneous")
        self._save_button.setEnabled(required <= self._captured.keys())

    def _accept_cookies(self) -> None:
        required = {"ipb_member_id", "ipb_pass_hash"}
        if self._site is GallerySite.EXHENTAI:
            required.add("igneous")
        missing = sorted(required - self._captured.keys())
        if missing:
            QMessageBox.warning(self, "网页登录", "尚未捕获：" + "、".join(missing))
            return
        self.accept()

    def done(self, result: int) -> None:
        self._view.stop()
        self._view.setUrl(QUrl("about:blank"))
        self._profile.cookieStore().deleteAllCookies()
        self._profile.clearHttpCache()
        super().done(result)
