from __future__ import annotations

import re
from dataclasses import dataclass
from html.parser import HTMLParser

import httpx

from app.models.gallery_status import GallerySite, GalleryStatus


@dataclass(frozen=True, slots=True)
class GalleryPageCheckResult:
    status: GalleryStatus
    note: str = ""
    replacement_gid: int | None = None
    replacement_token: str | None = None


class _ForumIdentityParser(HTMLParser):
    """Extract only the login markers used by the existing JHenTai flow."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.guest_marker = False
        self.invalid_profile_marker = False
        self._stack: list[tuple[str, set[str]]] = []
        self._username_parts: list[str] = []

    @property
    def username(self) -> str:
        return " ".join("".join(self._username_parts).split())

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        classes = set((attributes.get("class") or "").split())
        if attributes.get("id") == "userlinksguest":
            self.guest_marker = True
        if "pcen" in classes:
            self.invalid_profile_marker = True
        self._stack.append((tag.casefold(), classes))

    def handle_endtag(self, tag: str) -> None:
        target = tag.casefold()
        for index in range(len(self._stack) - 1, -1, -1):
            if self._stack[index][0] == target:
                del self._stack[index:]
                break

    def handle_data(self, data: str) -> None:
        tags = [item[0] for item in self._stack]
        inside_home = any("home" in item[1] for item in self._stack)
        if tags and tags[-1] == "a" and "b" in tags and inside_home:
            self._username_parts.append(data)


class GalleryPageStatusChecker:
    _REPLACED_LINK = re.compile(
        r"replaced by.{0,1000}?/g/(\d+)/([0-9a-fA-F]+)/?",
        re.IGNORECASE | re.DOTALL,
    )

    def __init__(
        self,
        cookies: dict[str, str] | None = None,
        timeout_seconds: float = 20.0,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        self._cookies = dict(cookies or {})
        self._client = httpx.Client(
            cookies=self._cookies,
            timeout=httpx.Timeout(timeout_seconds),
            follow_redirects=True,
            transport=transport,
            headers={"User-Agent": "Emangato/0.6"},
        )

    def close(self) -> None:
        self._client.close()

    def check(self, url: str) -> GalleryPageCheckResult:
        try:
            response = self._client.get(url)
        except (httpx.TimeoutException, httpx.NetworkError) as error:
            return GalleryPageCheckResult(GalleryStatus.NETWORK_ERROR, str(error))

        if response.status_code == 429:
            return GalleryPageCheckResult(GalleryStatus.RATE_LIMITED, "HTTP 429")
        if response.status_code >= 500:
            return GalleryPageCheckResult(
                GalleryStatus.NETWORK_ERROR,
                f"HTTP {response.status_code}",
            )
        if response.status_code in {401, 403}:
            return GalleryPageCheckResult(GalleryStatus.ACCESS_DENIED, f"HTTP {response.status_code}")

        text = response.text
        lowered = text.casefold()
        if "unavailable due to a copyright claim" in lowered:
            return GalleryPageCheckResult(GalleryStatus.COPYRIGHT_REMOVED, self._page_message(text))
        if "this gallery has been deleted" in lowered:
            return GalleryPageCheckResult(GalleryStatus.DELETED, self._page_message(text))
        if "this gallery has been removed or is unavailable" in lowered:
            return GalleryPageCheckResult(GalleryStatus.REMOVED, self._page_message(text))
        if "this gallery has been replaced" in lowered or "replaced by" in lowered:
            replacement = self._REPLACED_LINK.search(text)
            return GalleryPageCheckResult(
                GalleryStatus.REPLACED,
                self._page_message(text) or "页面明确标记为 replaced",
                int(replacement.group(1)) if replacement else None,
                replacement.group(2) if replacement else None,
            )
        if "this gallery has been expunged" in lowered or "gallery is expunged" in lowered:
            return GalleryPageCheckResult(GalleryStatus.EXPUNGED, self._page_message(text))
        if "sad panda" in lowered or response.url.host == "e-hentai.org" and "exhentai.org" in url:
            return GalleryPageCheckResult(GalleryStatus.ACCESS_DENIED, "ExHentai 登录状态无效")
        if response.status_code == 404:
            return GalleryPageCheckResult(GalleryStatus.UNKNOWN, "HTTP 404，页面提示无法可靠分类")
        return GalleryPageCheckResult(GalleryStatus.LATEST)

    def test_login(self, site: GallerySite) -> tuple[bool, str]:
        member_id = self._cookies.get("ipb_member_id", "").strip()
        pass_hash = self._cookies.get("ipb_pass_hash", "").strip()
        igneous = self._cookies.get("igneous", "").strip()
        if not member_id.isdigit() or int(member_id) <= 0 or not pass_hash:
            return False, "缺少有效的 ipb_member_id 或 ipb_pass_hash"
        if site is GallerySite.EXHENTAI and igneous.casefold() in {
            "", "null", "mystery", "deleted",
        }:
            return False, "ExHentai 需要有效的 igneous Cookie"

        # ExHentai's front page and E-Hentai's favorites page both require a
        # usable authenticated session.  The public E-Hentai index does not.
        url = (
            "https://exhentai.org/"
            if site is GallerySite.EXHENTAI
            else "https://e-hentai.org/favorites.php"
        )
        try:
            response = self._client.get(url)
        except (httpx.TimeoutException, httpx.NetworkError) as error:
            return False, f"网络错误：{error}"
        if response.status_code == 429:
            return False, "请求受到限制（HTTP 429）"
        if response.status_code >= 500:
            return False, f"站点错误：HTTP {response.status_code}"
        if response.status_code in {401, 403}:
            hint = "；可能是 Cloudflare，请使用网页登录验证" if response.status_code == 403 else ""
            return False, f"站点拒绝访问：HTTP {response.status_code}{hint}"
        if response.status_code != 200:
            return False, f"站点返回非预期状态：HTTP {response.status_code}"
        if response.url.host != site.host:
            return False, f"被重定向到 {response.url.host or '未知站点'}，Cookie 可能无效"
        lowered = response.text.casefold()
        if site is GallerySite.EXHENTAI and "sad panda" in lowered:
            return False, "ExHentai 返回 Sad Panda，Cookie 可能无效"
        if self._is_cloudflare_page(lowered):
            return False, "站点页面处于 Cloudflare 验证状态，请使用网页登录验证"
        if site is GallerySite.EHENTAI and self._is_login_required_page(lowered):
            return False, "E-Hentai 收藏页要求重新登录，Cookie 无效"

        site_evidence = (
            "ExHentai 可访问"
            if site is GallerySite.EXHENTAI
            else "E-Hentai 收藏页可访问"
        )

        profile_url = f"https://forums.e-hentai.org/index.php?showuser={member_id}"
        try:
            profile = self._client.get(profile_url)
        except (httpx.TimeoutException, httpx.NetworkError) as error:
            return True, f"{site_evidence}；论坛身份验证不可用（{error}）"
        if profile.status_code == 429:
            return True, f"{site_evidence}；论坛身份验证受到限制（HTTP 429）"
        if profile.status_code == 403:
            return True, f"{site_evidence}；论坛被 Cloudflare 拦截（HTTP 403），已跳过用户名验证"
        if profile.status_code >= 500:
            return True, f"{site_evidence}；论坛身份验证暂不可用（HTTP {profile.status_code}）"
        if profile.status_code != 200:
            return True, f"{site_evidence}；论坛身份验证返回 HTTP {profile.status_code}"

        profile_lowered = profile.text.casefold()
        if self._is_cloudflare_page(profile_lowered):
            return True, f"{site_evidence}；论坛处于 Cloudflare 验证页面，已跳过用户名验证"

        parser = _ForumIdentityParser()
        parser.feed(profile.text)
        if parser.guest_marker or parser.invalid_profile_marker:
            return False, "Cookie 无效，论坛页面仍处于游客状态"
        if not parser.username:
            return False, "未能从论坛资料页确认登录用户名"
        return True, f"已验证账号：{parser.username}；{site_evidence}"

    @staticmethod
    def _is_cloudflare_page(lowered_html: str) -> bool:
        return any(
            marker in lowered_html
            for marker in (
                "cf-chl-",
                "just a moment",
                "challenge-platform",
                "cloudflare ray id",
            )
        )

    @staticmethod
    def _is_login_required_page(lowered_html: str) -> bool:
        return any(
            marker in lowered_html
            for marker in (
                "this page requires you to log on",
                "you must be logged in",
                "act=login",
                "id=\"userlinksguest\"",
                "id='userlinksguest'",
            )
        )

    @staticmethod
    def _page_message(text: str) -> str:
        match = re.search(r"This gallery[^<\r\n.]*[.]?", text, re.IGNORECASE)
        return match.group(0).strip() if match else ""
