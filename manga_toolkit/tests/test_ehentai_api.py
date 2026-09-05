from pathlib import Path

import httpx
import pytest

from app.models.gallery_status import GalleryReference
from app.services.ehentai_api import (
    EhentaiApiClient,
    EhentaiMalformedResponseError,
    EhentaiNetworkError,
    EhentaiRateLimitedError,
)


def reference(gid: int = 100, token: str = "abc123") -> GalleryReference:
    return GalleryReference(Path("C:/Manga/item"), "metadata", gid, token, None, "title")


def test_current_gallery_metadata() -> None:
    transport = httpx.MockTransport(
        lambda request: httpx.Response(
            200,
            json={"gmetadata": [{"gid": 100, "token": "abc123", "title": "A", "filecount": "10", "filesize": 20}]},
        )
    )
    with EhentaiApiClient(transport=transport) as client:
        result = client.fetch_metadata([reference()])[0]
    assert result.gid == 100
    assert result.filecount == 10


def test_current_gid_different_is_returned() -> None:
    transport = httpx.MockTransport(
        lambda request: httpx.Response(
            200,
            json={"gmetadata": [{"gid": 100, "token": "abc123", "current_gid": "200", "current_key": "def456"}]},
        )
    )
    with EhentaiApiClient(transport=transport) as client:
        result = client.fetch_metadata([reference()])[0]
    assert result.current_gid == 200
    assert result.current_token == "def456"


def test_token_invalid_is_data_not_deleted() -> None:
    transport = httpx.MockTransport(
        lambda request: httpx.Response(
            200,
            json={"gmetadata": [{"gid": 100, "error": "Key missing, or incorrect key provided."}]},
        )
    )
    with EhentaiApiClient(transport=transport) as client:
        result = client.fetch_metadata([reference()])[0]
    assert "incorrect key" in result.error


def test_api_timeout() -> None:
    def timeout(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("timeout", request=request)

    with EhentaiApiClient(transport=httpx.MockTransport(timeout)) as client:
        with pytest.raises(EhentaiNetworkError):
            client.fetch_metadata([reference()])


def test_api_rate_limited() -> None:
    transport = httpx.MockTransport(lambda request: httpx.Response(429, text="rate limited"))
    with EhentaiApiClient(transport=transport) as client:
        with pytest.raises(EhentaiRateLimitedError):
            client.fetch_metadata([reference()])


def test_malformed_api_json() -> None:
    transport = httpx.MockTransport(lambda request: httpx.Response(200, text="not-json"))
    with EhentaiApiClient(transport=transport) as client:
        with pytest.raises(EhentaiMalformedResponseError):
            client.fetch_metadata([reference()])


def test_missing_metadata_item_is_malformed_not_latest() -> None:
    transport = httpx.MockTransport(
        lambda request: httpx.Response(200, json={"gmetadata": []}, request=request)
    )
    with EhentaiApiClient(transport=transport) as client:
        with pytest.raises(EhentaiMalformedResponseError):
            client.fetch_metadata([reference()])


def test_api_never_sends_more_than_25() -> None:
    transport = httpx.MockTransport(lambda request: httpx.Response(200, json={"gmetadata": []}))
    references = [reference(index + 1, f"abc{index}") for index in range(26)]
    with EhentaiApiClient(transport=transport) as client:
        with pytest.raises(ValueError):
            client.fetch_metadata(references)
