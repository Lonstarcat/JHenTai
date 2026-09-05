from pathlib import Path

from app.models.gallery_status import (
    GalleryMetadataSnapshot,
    GalleryReference,
    GallerySite,
    GalleryStatus,
    GalleryStatusRecord,
)
from app.services.ehentai_api import EhentaiNetworkError, EhentaiRateLimitedError
from app.services.gallery_page_checker import GalleryPageCheckResult
from app.services.gallery_status_service import GalleryStatusService, StatusCheckOptions


class FakeCache:
    def __init__(self) -> None:
        self.records: list[GalleryStatusRecord] = []

    def get(self, reference: GalleryReference):
        return None

    def is_fresh(self, record: GalleryStatusRecord, cache_hours: int) -> bool:
        return False

    def save(self, record: GalleryStatusRecord) -> None:
        self.records.append(record)


class FakePageChecker:
    def check(self, url: str) -> GalleryPageCheckResult:
        return GalleryPageCheckResult(GalleryStatus.LATEST)


class ExpungedPageChecker:
    def check(self, url: str) -> GalleryPageCheckResult:
        return GalleryPageCheckResult(GalleryStatus.EXPUNGED, "This gallery has been expunged.")


class FakeApi:
    def __init__(self, responses: list[object]) -> None:
        self.responses = responses
        self.calls = 0

    def fetch_metadata(self, references):
        response = self.responses[self.calls]
        self.calls += 1
        if isinstance(response, Exception):
            raise response
        return response


def ref() -> GalleryReference:
    return GalleryReference(Path("C:/Manga/100 - item"), "metadata", 100, "abc123", None, "item")


def options() -> StatusCheckOptions:
    return StatusCheckOptions(
        site=GallerySite.EHENTAI,
        request_interval=0,
        pause_seconds=0,
        retries=0,
    )


def test_latest_status() -> None:
    api = FakeApi([[GalleryMetadataSnapshot(100, "abc123", current_gid=100, current_token="abc123")]])
    result = GalleryStatusService(api, FakePageChecker(), FakeCache(), lambda _: None).check([ref()], options())
    assert result.records[0].status is GalleryStatus.LATEST


def test_update_available_and_latest_metadata_comparison() -> None:
    old = GalleryMetadataSnapshot(100, "abc123", filecount=10, filesize=100, current_gid=200, current_token="def456")
    new = GalleryMetadataSnapshot(200, "def456", title="new", filecount=12, filesize=150)
    api = FakeApi([[old], [new]])
    result = GalleryStatusService(api, FakePageChecker(), FakeCache(), lambda _: None).check([ref()], options())
    record = result.records[0]
    assert record.status is GalleryStatus.UPDATE_AVAILABLE
    assert record.current_gid == 200
    assert record.page_delta == 2
    assert record.size_delta == 50


def test_token_invalid_never_becomes_deleted() -> None:
    snapshot = GalleryMetadataSnapshot(100, "abc123", error="Key missing, or incorrect key provided.")
    result = GalleryStatusService(FakeApi([[snapshot]]), FakePageChecker(), FakeCache(), lambda _: None).check([ref()], options())
    assert result.records[0].status is GalleryStatus.TOKEN_INVALID


def test_network_error_never_becomes_removed() -> None:
    result = GalleryStatusService(
        FakeApi([EhentaiNetworkError("timeout")]), FakePageChecker(), FakeCache(), lambda _: None
    ).check([ref()], options())
    assert result.records[0].status is GalleryStatus.NETWORK_ERROR


def test_429_is_rate_limited() -> None:
    result = GalleryStatusService(
        FakeApi([EhentaiRateLimitedError("429")]), FakePageChecker(), FakeCache(), lambda _: None
    ).check([ref()], options())
    assert result.records[0].status is GalleryStatus.RATE_LIMITED


def test_suspicious_api_result_can_be_confirmed_as_expunged() -> None:
    snapshot = GalleryMetadataSnapshot(100, "abc123", error="unclassified API response")
    result = GalleryStatusService(
        FakeApi([[snapshot]]), ExpungedPageChecker(), FakeCache(), lambda _: None
    ).check([ref()], options())
    assert result.records[0].status is GalleryStatus.EXPUNGED
