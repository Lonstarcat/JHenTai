import httpx

from app.models.gallery_status import GallerySite, GalleryStatus
from app.services.gallery_page_checker import GalleryPageStatusChecker


def check_html(html: str, status_code: int = 200):
    transport = httpx.MockTransport(lambda request: httpx.Response(status_code, text=html, request=request))
    checker = GalleryPageStatusChecker(transport=transport)
    try:
        return checker.check("https://e-hentai.org/g/100/abc123/")
    finally:
        checker.close()


def test_removed_page() -> None:
    result = check_html("<p>This gallery has been removed or is unavailable.</p>")
    assert result.status is GalleryStatus.REMOVED


def test_copyright_removed_page() -> None:
    result = check_html("<p>This gallery is unavailable due to a copyright claim by X.</p>")
    assert result.status is GalleryStatus.COPYRIGHT_REMOVED


def test_expunged_page() -> None:
    result = check_html("<p>This gallery has been expunged.</p>")
    assert result.status is GalleryStatus.EXPUNGED


def test_replaced_page_only_uses_explicit_replacement_link() -> None:
    result = check_html(
        '<p>This gallery has been replaced by <a href="/g/200/def456/">another gallery</a>.</p>'
    )
    assert result.status is GalleryStatus.REPLACED
    assert result.replacement_gid == 200
    assert result.replacement_token == "def456"


def test_http_500_is_network_error() -> None:
    result = check_html("temporary error", status_code=503)
    assert result.status is GalleryStatus.NETWORK_ERROR


def test_login_requires_complete_account_cookies_without_requesting_network() -> None:
    def unexpected_request(request: httpx.Request) -> httpx.Response:
        raise AssertionError("missing credentials must fail before the network request")

    checker = GalleryPageStatusChecker(
        cookies={"ipb_member_id": "123"},
        transport=httpx.MockTransport(unexpected_request),
    )
    try:
        success, message = checker.test_login(GallerySite.EHENTAI)
    finally:
        checker.close()
    assert success is False
    assert "ipb_pass_hash" in message


def test_login_confirms_forum_identity_not_only_http_200() -> None:
    def response(request: httpx.Request) -> httpx.Response:
        if request.url.host == "forums.e-hentai.org":
            html = '<div class="home"><b><a href="/user">Test User</a></b></div><div id="profilename">Profile</div>'
        else:
            html = "<html><title>E-Hentai Galleries</title></html>"
        return httpx.Response(200, text=html, request=request)

    checker = GalleryPageStatusChecker(
        cookies={"ipb_member_id": "123", "ipb_pass_hash": "hash"},
        transport=httpx.MockTransport(response),
    )
    try:
        success, message = checker.test_login(GallerySite.EHENTAI)
    finally:
        checker.close()
    assert success is True
    assert "Test User" in message


def test_login_rejects_guest_forum_page_even_when_both_requests_return_200() -> None:
    def response(request: httpx.Request) -> httpx.Response:
        html = '<div id="userlinksguest">You are not logged in</div>' if request.url.host == "forums.e-hentai.org" else "ok"
        return httpx.Response(200, text=html, request=request)

    checker = GalleryPageStatusChecker(
        cookies={"ipb_member_id": "123", "ipb_pass_hash": "wrong"},
        transport=httpx.MockTransport(response),
    )
    try:
        success, message = checker.test_login(GallerySite.EHENTAI)
    finally:
        checker.close()
    assert success is False
    assert "游客" in message


def test_exhentai_login_requires_valid_igneous() -> None:
    checker = GalleryPageStatusChecker(
        cookies={"ipb_member_id": "123", "ipb_pass_hash": "hash", "igneous": "mystery"},
        transport=httpx.MockTransport(lambda request: httpx.Response(200, request=request)),
    )
    try:
        success, message = checker.test_login(GallerySite.EXHENTAI)
    finally:
        checker.close()
    assert success is False
    assert "igneous" in message


def test_login_accepts_protected_site_when_forum_is_blocked_by_cloudflare() -> None:
    def response(request: httpx.Request) -> httpx.Response:
        if request.url.host == "forums.e-hentai.org":
            return httpx.Response(403, text="cloudflare", request=request)
        return httpx.Response(200, text="<html>favorites</html>", request=request)

    checker = GalleryPageStatusChecker(
        cookies={"ipb_member_id": "123", "ipb_pass_hash": "hash"},
        transport=httpx.MockTransport(response),
    )
    try:
        success, message = checker.test_login(GallerySite.EHENTAI)
    finally:
        checker.close()
    assert success is True
    assert "Cloudflare" in message
    assert "收藏页可访问" in message


def test_login_does_not_ignore_cloudflare_on_protected_site_itself() -> None:
    checker = GalleryPageStatusChecker(
        cookies={"ipb_member_id": "123", "ipb_pass_hash": "hash"},
        transport=httpx.MockTransport(
            lambda request: httpx.Response(403, text="cloudflare", request=request)
        ),
    )
    try:
        success, message = checker.test_login(GallerySite.EHENTAI)
    finally:
        checker.close()
    assert success is False
    assert "网页登录" in message


def test_login_accepts_site_when_forum_returns_cloudflare_challenge_html() -> None:
    def response(request: httpx.Request) -> httpx.Response:
        if request.url.host == "forums.e-hentai.org":
            return httpx.Response(200, text="<title>Just a moment...</title><div id='cf-chl-widget'></div>", request=request)
        return httpx.Response(200, text="favorites", request=request)

    checker = GalleryPageStatusChecker(
        cookies={"ipb_member_id": "123", "ipb_pass_hash": "hash"},
        transport=httpx.MockTransport(response),
    )
    try:
        success, message = checker.test_login(GallerySite.EHENTAI)
    finally:
        checker.close()
    assert success is True
    assert "Cloudflare" in message
