from __future__ import annotations

from PySide6.QtCore import QTimer, QUrl
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

    def __init__(
        self,
        site: GallerySite,
        initial_cookies: dict[str, str] | None = None,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self._site = site
        self._captured: dict[str, str] = dict(initial_cookies or {})
        self._forum_verified = False
        self._site_verified = False
        self._verified_identity = ""
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
        self._inject_existing_cookies()
        self._view = QWebEngineView(self)
        self._view.setPage(QWebEnginePage(self._profile, self._view))
        self._view.loadFinished.connect(self._inspect_loaded_page)
        QTimer.singleShot(0, lambda: self._view.setUrl(QUrl(self.LOGIN_URL)))
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

    @property
    def browser_verified(self) -> bool:
        return self._site_verified if self._site is GallerySite.EXHENTAI else self._forum_verified

    @property
    def verification_message(self) -> str:
        if self._site is GallerySite.EXHENTAI and self._site_verified:
            return f"WebView 已验证 ExHentai 访问和论坛身份：{self._verified_identity or '已登录'}"
        if self._forum_verified:
            return f"WebView 已验证论坛身份：{self._verified_identity or '已登录'}"
        return "已捕获 Cookie，尚未在浏览器内确认登录页面"

    def _inject_existing_cookies(self) -> None:
        store = self._profile.cookieStore()
        for name, value in self._captured.items():
            if name not in self.ALLOWED_COOKIES or not value:
                continue
            cookie = QNetworkCookie(name.encode("ascii"), value.encode("utf-8"))
            origin = self.EX_URL if name == "igneous" else "https://e-hentai.org/"
            cookie.setDomain(".exhentai.org" if name == "igneous" else ".e-hentai.org")
            cookie.setPath("/")
            cookie.setSecure(True)
            store.setCookie(cookie, QUrl(origin))

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

    def _inspect_loaded_page(self, loaded: bool) -> None:
        if not loaded:
            self._status.setText("页面加载失败；可重试或检查网络")
            return
        script = """
        (() => {
          const text = (document.body?.innerText || '').toLowerCase();
          const title = (document.title || '').toLowerCase();
          return {
            url: window.location.href,
            guest: Boolean(document.querySelector('#userlinksguest')),
            username: (document.querySelector('.home > b > a')?.innerText || '').trim(),
            cloudflare: Boolean(document.querySelector('#challenge-running, #challenge-stage, .cf-challenge-running'))
              || title.includes('just a moment') || text.includes('cloudflare ray id'),
            sadPanda: text.includes('sad panda')
          };
        })()
        """
        self._view.page().runJavaScript(script, self._handle_page_evidence)

    def _handle_page_evidence(self, evidence: object) -> None:
        if not isinstance(evidence, dict):
            return
        if evidence.get("cloudflare"):
            self._status.setText("正在等待 Cloudflare 验证完成…")
            return
        url = str(evidence.get("url") or "")
        username = str(evidence.get("username") or "").strip()
        if "forums.e-hentai.org" in url:
            if evidence.get("guest"):
                self._status.setText("论坛仍为游客状态，请完成登录")
            elif username:
                self._forum_verified = True
                self._verified_identity = username
                self._status.setText(f"论坛已验证：{username}" + ("；请继续访问 ExHentai" if self._site is GallerySite.EXHENTAI else ""))
        elif "exhentai.org" in url:
            if evidence.get("sadPanda"):
                self._site_verified = False
                self._status.setText("ExHentai 返回 Sad Panda，请重新登录或刷新 igneous")
            elif self._forum_verified and "igneous" in self._captured:
                self._site_verified = True
                self._status.setText(f"ExHentai 与论坛身份均已验证：{self._verified_identity}")

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
