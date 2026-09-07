from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import httpx

from app.models.gallery_status import GalleryMetadataSnapshot, GalleryReference


class EhentaiApiError(RuntimeError):
    pass


class EhentaiNetworkError(EhentaiApiError):
    pass


class EhentaiRateLimitedError(EhentaiApiError):
    pass


class EhentaiMalformedResponseError(EhentaiApiError):
    pass


class EhentaiApiClient:
    API_URL = "https://api.e-hentai.org/api.php"
    MAX_BATCH_SIZE = 25

    def __init__(
        self,
        cookies: dict[str, str] | None = None,
        timeout_seconds: float = 20.0,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        self._client = httpx.Client(
            cookies=cookies or {},
            timeout=httpx.Timeout(timeout_seconds),
            follow_redirects=True,
            transport=transport,
            headers={"User-Agent": "Emangato/0.6"},
        )

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "EhentaiApiClient":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def fetch_metadata(
        self,
        references: Sequence[GalleryReference],
    ) -> list[GalleryMetadataSnapshot]:
        if not references:
            return []
        if len(references) > self.MAX_BATCH_SIZE:
            raise ValueError("E-Hentai API 每批最多允许 25 个画廊")
        if any(reference.gid is None or not reference.token for reference in references):
            raise ValueError("API 请求包含缺少 gid/token 的画廊")

        payload = {
            "method": "gdata",
            "gidlist": [[reference.gid, reference.token] for reference in references],
            "namespace": 1,
        }
        try:
            response = self._client.post(self.API_URL, json=payload)
        except (httpx.TimeoutException, httpx.NetworkError) as error:
            raise EhentaiNetworkError(str(error)) from error

        if response.status_code == 429:
            raise EhentaiRateLimitedError("E-Hentai API 返回 HTTP 429")
        if response.status_code >= 500:
            raise EhentaiNetworkError(f"E-Hentai API 返回 HTTP {response.status_code}")
        if response.status_code in {401, 403}:
            raise EhentaiApiError(f"E-Hentai API 拒绝访问：HTTP {response.status_code}")

        try:
            response.raise_for_status()
            payload_data = response.json()
        except (httpx.HTTPStatusError, ValueError) as error:
            raise EhentaiMalformedResponseError(str(error)) from error
        if not isinstance(payload_data, dict) or not isinstance(payload_data.get("gmetadata"), list):
            raise EhentaiMalformedResponseError("API 响应缺少 gmetadata 数组")

        raw_items = payload_data["gmetadata"]
        if len(raw_items) != len(references) or any(not isinstance(item, dict) for item in raw_items):
            raise EhentaiMalformedResponseError(
                "API 返回的 gmetadata 数量或结构与请求不一致"
            )
        snapshots: list[GalleryMetadataSnapshot] = []
        for raw, reference in zip(raw_items, references, strict=True):
            snapshots.append(self._parse_snapshot(raw, reference))
        return snapshots

    @classmethod
    def _parse_snapshot(
        cls,
        raw: dict[str, Any],
        reference: GalleryReference,
    ) -> GalleryMetadataSnapshot:
        gid = cls._to_int(raw.get("gid")) or reference.gid or 0
        token = cls._to_text(raw.get("token")) or reference.token or ""
        tags = raw.get("tags")
        return GalleryMetadataSnapshot(
            gid=gid,
            token=token,
            title=cls._to_text(raw.get("title")),
            title_jpn=cls._to_text(raw.get("title_jpn")),
            filecount=cls._to_int(raw.get("filecount")),
            filesize=cls._to_int(raw.get("filesize")),
            posted=cls._to_int(raw.get("posted")),
            category=cls._to_text(raw.get("category")),
            tags=tuple(str(tag) for tag in tags) if isinstance(tags, list) else (),
            expunged=bool(raw.get("expunged", False)),
            parent_gid=cls._positive_int(raw.get("parent_gid")),
            parent_token=cls._to_text(raw.get("parent_key")) or None,
            current_gid=cls._positive_int(raw.get("current_gid")),
            current_token=cls._to_text(raw.get("current_key")) or None,
            first_gid=cls._positive_int(raw.get("first_gid")),
            first_token=cls._to_text(raw.get("first_key")) or None,
            error=cls._to_text(raw.get("error")),
        )

    @staticmethod
    def _to_text(value: object) -> str:
        return str(value).strip() if value is not None else ""

    @staticmethod
    def _to_int(value: object) -> int | None:
        try:
            return int(value) if value is not None and str(value).strip() else None
        except (TypeError, ValueError):
            return None

    @classmethod
    def _positive_int(cls, value: object) -> int | None:
        result = cls._to_int(value)
        return result if result is not None and result > 0 else None
