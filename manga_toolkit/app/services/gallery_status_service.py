from __future__ import annotations

import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass, replace
from datetime import UTC, datetime
from enum import StrEnum

from app.models.gallery_status import (
    ERROR_STATUSES,
    GalleryMetadataSnapshot,
    GalleryReference,
    GallerySite,
    GalleryStatus,
    GalleryStatusRecord,
    GalleryStatusRunSummary,
)
from app.services.ehentai_api import (
    EhentaiApiClient,
    EhentaiApiError,
    EhentaiMalformedResponseError,
    EhentaiNetworkError,
    EhentaiRateLimitedError,
)
from app.services.gallery_cache_service import GalleryCacheService
from app.services.gallery_page_checker import GalleryPageStatusChecker


class StatusCheckMode(StrEnum):
    ALL = "all"
    NEVER_CHECKED = "never_checked"
    EXPIRED = "expired"
    ERRORS = "errors"
    UPDATES = "updates"


@dataclass(frozen=True, slots=True)
class StatusCheckOptions:
    site: GallerySite = GallerySite.EXHENTAI
    batch_size: int = 25
    request_interval: float = 1.0
    pause_every_batches: int = 4
    pause_seconds: float = 5.0
    retries: int = 2
    cache_hours: int = 24

    def __post_init__(self) -> None:
        if not 1 <= self.batch_size <= 25:
            raise ValueError("batch_size 必须在 1～25 之间")
        if self.pause_every_batches < 1:
            raise ValueError("pause_every_batches 必须大于 0")


ProgressCallback = Callable[[int, int, str], None]
RecordCallback = Callable[[GalleryStatusRecord], None]
CancelCallback = Callable[[], bool]
SleepFunction = Callable[[float], None]


class GalleryStatusService:
    def __init__(
        self,
        api_client: EhentaiApiClient,
        page_checker: GalleryPageStatusChecker,
        cache: GalleryCacheService,
        sleep_function: SleepFunction = time.sleep,
    ) -> None:
        self._api = api_client
        self._page_checker = page_checker
        self._cache = cache
        self._sleep = sleep_function

    def check(
        self,
        references: Sequence[GalleryReference],
        options: StatusCheckOptions,
        mode: StatusCheckMode = StatusCheckMode.ALL,
        force_refresh: bool = False,
        on_progress: ProgressCallback | None = None,
        on_record: RecordCallback | None = None,
        is_cancelled: CancelCallback | None = None,
    ) -> GalleryStatusRunSummary:
        self._request_count = 0
        summary = GalleryStatusRunSummary()
        pending: list[GalleryReference] = []
        total = len(references)

        for reference in references:
            if is_cancelled and is_cancelled():
                summary.cancelled = True
                return summary
            cached = self._cache.get(reference)
            if reference.gid is None or not reference.token:
                record = GalleryStatusRecord(
                    reference=reference,
                    status=GalleryStatus.UNKNOWN,
                    checked_at=datetime.now(UTC),
                    note=reference.parse_error or "metadata 缺少 gid/token",
                )
                self._append_record(summary, record, on_record)
                continue

            should_check = self._should_check(cached, mode, options.cache_hours)
            if force_refresh:
                should_check = True
            if not should_check and cached is not None:
                self._append_record(summary, cached, on_record)
                summary.cache_hits += 1
                summary.skipped += 1
            elif should_check:
                pending.append(reference)
            else:
                summary.skipped += 1

        completed = total - len(pending)
        for batch_index, start in enumerate(range(0, len(pending), options.batch_size), start=1):
            if is_cancelled and is_cancelled():
                summary.cancelled = True
                break
            batch = pending[start : start + options.batch_size]
            if on_progress:
                on_progress(completed, total, f"正在请求第 {batch_index} 批（{len(batch)} 条）")

            try:
                snapshots = self._fetch_with_retry(batch, options, is_cancelled)
                records = [
                    self._record_from_snapshot(reference, snapshot, options.site)
                    for reference, snapshot in zip(batch, snapshots, strict=True)
                ]
                records = self._confirm_suspicious(records, options, is_cancelled)
                records = self._load_current_metadata(records, options, is_cancelled)
            except EhentaiRateLimitedError as error:
                records = self._batch_error_records(batch, GalleryStatus.RATE_LIMITED, str(error))
            except EhentaiNetworkError as error:
                records = self._batch_error_records(batch, GalleryStatus.NETWORK_ERROR, str(error))
            except EhentaiMalformedResponseError as error:
                records = self._confirm_suspicious(
                    self._batch_error_records(batch, GalleryStatus.UNKNOWN, f"API 响应异常：{error}"),
                    options,
                    is_cancelled,
                )
            except EhentaiApiError as error:
                records = self._confirm_suspicious(
                    self._batch_error_records(batch, GalleryStatus.UNKNOWN, str(error)),
                    options,
                    is_cancelled,
                )

            for record in records:
                if is_cancelled and is_cancelled():
                    summary.cancelled = True
                    break
                self._cache.save(record)
                self._append_record(summary, record, on_record)
                completed += 1
                if on_progress:
                    on_progress(completed, total, record.reference.local_title)
            if summary.cancelled:
                break

        return summary

    def _fetch_with_retry(
        self,
        references: Sequence[GalleryReference],
        options: StatusCheckOptions,
        is_cancelled: CancelCallback | None,
    ) -> list[GalleryMetadataSnapshot]:
        last_error: EhentaiApiError | None = None
        for attempt in range(options.retries + 1):
            if is_cancelled and is_cancelled():
                raise EhentaiNetworkError("任务已取消")
            try:
                if not self._throttle_api_request(options, is_cancelled):
                    raise EhentaiNetworkError("任务已取消")
                result = self._api.fetch_metadata(references)
                self._request_count += 1
                return result
            except (EhentaiNetworkError, EhentaiRateLimitedError) as error:
                self._request_count += 1
                last_error = error
                if attempt >= options.retries:
                    raise
                delay = max(options.request_interval, float(2**attempt))
                if not self._interruptible_sleep(delay, is_cancelled):
                    raise EhentaiNetworkError("任务已取消") from error
        raise last_error or EhentaiNetworkError("请求失败")

    def _record_from_snapshot(
        self,
        reference: GalleryReference,
        snapshot: GalleryMetadataSnapshot,
        site: GallerySite,
    ) -> GalleryStatusRecord:
        now = datetime.now(UTC)
        if snapshot.error:
            status = (
                GalleryStatus.TOKEN_INVALID
                if "key missing" in snapshot.error.casefold() or "incorrect key" in snapshot.error.casefold()
                else GalleryStatus.UNKNOWN
            )
            return GalleryStatusRecord(
                reference=reference,
                status=status,
                checked_at=now,
                local_metadata=snapshot,
                error=snapshot.error,
            )

        current_gid = snapshot.current_gid or snapshot.gid
        current_token = snapshot.current_token or snapshot.token
        if snapshot.category.casefold() == "private":
            status = GalleryStatus.PRIVATE
        elif snapshot.expunged:
            status = GalleryStatus.EXPUNGED
        elif snapshot.current_gid and snapshot.current_gid != reference.gid:
            status = GalleryStatus.UPDATE_AVAILABLE
        elif (snapshot.parent_gid or snapshot.first_gid) and snapshot.current_gid is None:
            status = GalleryStatus.UNKNOWN_CHAIN
        else:
            status = GalleryStatus.LATEST

        return GalleryStatusRecord(
            reference=reference,
            status=status,
            checked_at=now,
            local_metadata=snapshot,
            current_metadata=snapshot if current_gid == snapshot.gid else None,
            current_gid=current_gid,
            current_token=current_token,
            first_gid=snapshot.first_gid,
            parent_gid=snapshot.parent_gid,
            latest_url=reference.build_url(site, current_gid, current_token),
        )

    def _confirm_suspicious(
        self,
        records: list[GalleryStatusRecord],
        options: StatusCheckOptions,
        is_cancelled: CancelCallback | None,
    ) -> list[GalleryStatusRecord]:
        confirmed: list[GalleryStatusRecord] = []
        definitive = {
            GalleryStatus.EXPUNGED,
            GalleryStatus.REPLACED,
            GalleryStatus.REMOVED,
            GalleryStatus.COPYRIGHT_REMOVED,
            GalleryStatus.DELETED,
            GalleryStatus.ACCESS_DENIED,
            GalleryStatus.RATE_LIMITED,
            GalleryStatus.NETWORK_ERROR,
        }
        for record in records:
            if record.status not in {GalleryStatus.EXPUNGED, GalleryStatus.UNKNOWN}:
                confirmed.append(record)
                continue
            if is_cancelled and is_cancelled():
                confirmed.append(record)
                continue
            url = record.reference.build_url(options.site)
            if not url:
                confirmed.append(record)
                continue
            page_result = self._page_checker.check(url)
            if page_result.status in definitive:
                replacement_url = record.reference.build_url(
                    options.site,
                    page_result.replacement_gid,
                    page_result.replacement_token,
                )
                confirmed.append(
                    replace(
                        record,
                        status=page_result.status,
                        replacement_gid=page_result.replacement_gid,
                        replacement_token=page_result.replacement_token,
                        replacement_url=replacement_url,
                        note=page_result.note or record.note,
                    )
                )
            else:
                confirmed.append(
                    replace(record, note=page_result.note or record.note)
                )
            self._interruptible_sleep(options.request_interval, is_cancelled)
        return confirmed

    def _load_current_metadata(
        self,
        records: list[GalleryStatusRecord],
        options: StatusCheckOptions,
        is_cancelled: CancelCallback | None,
    ) -> list[GalleryStatusRecord]:
        update_positions: list[int] = []
        current_references: list[GalleryReference] = []
        for index, record in enumerate(records):
            if (
                record.status is GalleryStatus.UPDATE_AVAILABLE
                and record.current_gid is not None
                and record.current_token
            ):
                update_positions.append(index)
                current_references.append(
                    replace(
                        record.reference,
                        gid=record.current_gid,
                        token=record.current_token,
                        gallery_url=record.latest_url,
                    )
                )
        if not current_references or (is_cancelled and is_cancelled()):
            return records

        try:
            snapshots = self._fetch_with_retry(current_references, options, is_cancelled)
        except EhentaiApiError as error:
            return [
                replace(record, error=f"最新版本 metadata 获取失败：{error}")
                if index in update_positions
                else record
                for index, record in enumerate(records)
            ]
        updated = list(records)
        for position, snapshot in zip(update_positions, snapshots, strict=True):
            updated[position] = replace(updated[position], current_metadata=snapshot)
        return updated

    def _should_check(
        self,
        cached: GalleryStatusRecord | None,
        mode: StatusCheckMode,
        cache_hours: int,
    ) -> bool:
        if mode is StatusCheckMode.NEVER_CHECKED:
            return cached is None
        if mode is StatusCheckMode.EXPIRED:
            return cached is None or not self._cache.is_fresh(cached, cache_hours)
        if mode is StatusCheckMode.ERRORS:
            return cached is not None and cached.status in ERROR_STATUSES
        if mode is StatusCheckMode.UPDATES:
            return cached is not None and cached.status is GalleryStatus.UPDATE_AVAILABLE
        return cached is None or not self._cache.is_fresh(cached, cache_hours)

    @staticmethod
    def _batch_error_records(
        references: Sequence[GalleryReference],
        status: GalleryStatus,
        error: str,
    ) -> list[GalleryStatusRecord]:
        checked_at = datetime.now(UTC)
        return [
            GalleryStatusRecord(
                reference=reference,
                status=status,
                checked_at=checked_at,
                error=error,
            )
            for reference in references
        ]

    @staticmethod
    def _append_record(
        summary: GalleryStatusRunSummary,
        record: GalleryStatusRecord,
        callback: RecordCallback | None,
    ) -> None:
        summary.records.append(record)
        if callback:
            callback(record)

    def _interruptible_sleep(
        self,
        seconds: float,
        is_cancelled: CancelCallback | None,
    ) -> bool:
        remaining = max(0.0, seconds)
        while remaining > 0:
            if is_cancelled and is_cancelled():
                return False
            duration = min(0.1, remaining)
            self._sleep(duration)
            remaining -= duration
        return not (is_cancelled and is_cancelled())

    def _throttle_api_request(
        self,
        options: StatusCheckOptions,
        is_cancelled: CancelCallback | None,
    ) -> bool:
        if self._request_count == 0:
            return True
        delay = (
            options.pause_seconds
            if self._request_count % options.pause_every_batches == 0
            else options.request_interval
        )
        return self._interruptible_sleep(delay, is_cancelled)
