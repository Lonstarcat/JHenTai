#!/usr/bin/env python3
"""从 JHenTai metadata 批量补齐 ComicInfo.xml（Windows/标准库版本）。

此脚本只会：
1. 递归查找名为 ``metadata`` 或 ``ametadata`` 的 JHenTai 元数据文件；
2. 调用 EHentai gdata API 获取画廊信息；
3. 在 metadata 所在目录写入 ``ComicInfo.xml``；
4. 在根目录的 ``comicinfo_reports`` 中写入处理报告。

它不会修改 metadata/ametadata、图片、文件夹名称或 CBZ 文件。

需要 Python 3.10 或更高版本。若需要访问 ExHentai，可准备 cookies.json：
{"ipb_member_id": "...", "ipb_pass_hash": "...", "igneous": "..."}
Cookie 和 gallery token 都不会写入处理报告。
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Sequence


EH_API_URL = "https://api.e-hentai.org/api.php"
EX_API_URL = "https://exhentai.org/api.php"
DEFAULT_GALLERY_BASE_URL = "https://exhentai.org"
COMICINFO_NAME = "ComicInfo.xml"
REPORT_DIR_NAME = "comicinfo_reports"
METADATA_FILE_NAMES = {"metadata", "ametadata"}
MAX_API_BATCH_SIZE = 25
GALLERY_URL_RE = re.compile(
    r"https?://(?:e-hentai\.org|exhentai\.org)/g/(\d+)/([0-9a-fA-F]+)/?",
    re.IGNORECASE,
)
LANGUAGE_TO_ISO = {
    "chinese": "zh",
    "japanese": "jp",  # 与当前 JHenTai 的 LocaleConsts 保持一致
    "english": "en",
    "korean": "kr",
    "spanish": "es",
    "portuguese": "pt",
    "russian": "ru",
    "french": "fr",
    "italian": "it",
    "german": "de",
    "polish": "pl",
    "hungarian": "hu",
    "thai": "th",
    "dutch": "nl",
    "vietnamese": "vi",
}


@dataclass
class GalleryFolder:
    folder: Path
    metadata_path: Path
    gid: int | None = None
    token: str | None = None
    gallery_url: str | None = None
    title: str = ""
    metadata_kind: str = "unknown"
    scan_status: str = "pending"
    message: str = ""
    comicinfo_exists: bool = False

    @property
    def key(self) -> tuple[int, str] | None:
        if self.gid is None or not self.token:
            return None
        return self.gid, self.token.lower()


@dataclass
class Result:
    folder: GalleryFolder
    status: str
    message: str = ""


@dataclass
class ApiResult:
    metadata_by_key: dict[tuple[int, str], dict[str, Any]] = field(default_factory=dict)
    errors_by_key: dict[tuple[int, str], str] = field(default_factory=dict)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="扫描 JHenTai metadata，并在各漫画文件夹内生成 ComicInfo.xml。",
    )
    parser.add_argument("root", type=Path, help=r"包含漫画文件夹的根目录，例如 D:\JHenTai\MissingComicInfo")
    parser.add_argument("--scan-only", action="store_true", help="只扫描和生成报告，不联网、不写 ComicInfo.xml")
    parser.add_argument("--overwrite", action="store_true", help="覆盖已经存在且可解析的 ComicInfo.xml")
    parser.add_argument("--cookies", type=Path, help="可选的 cookies.json；用于需要登录权限的请求")
    parser.add_argument("--batch-size", type=int, default=20, help="每次 API 请求的画廊数，默认 20，最大 25")
    parser.add_argument("--interval", type=float, default=2.0, help="每批请求完成后的等待秒数，默认 2.0")
    parser.add_argument("--retries", type=int, default=4, help="网络请求最大尝试次数，默认 4")
    parser.add_argument("--timeout", type=float, default=30.0, help="单次请求超时秒数，默认 30")
    parser.add_argument("--api-url", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)

    if not 1 <= args.batch_size <= MAX_API_BATCH_SIZE:
        parser.error(f"--batch-size 必须在 1 到 {MAX_API_BATCH_SIZE} 之间")
    if args.interval < 0:
        parser.error("--interval 不能为负数")
    if args.retries < 1:
        parser.error("--retries 至少为 1")
    if args.timeout <= 0:
        parser.error("--timeout 必须大于 0")
    return args


def configure_windows_console() -> None:
    """尽量让 Windows 控制台正确显示中文；旧终端不支持时静默跳过。"""
    for stream_name in ("stdout", "stderr"):
        stream = getattr(sys, stream_name, None)
        if stream is not None and hasattr(stream, "reconfigure"):
            try:
                stream.reconfigure(encoding="utf-8", errors="replace")
            except (LookupError, OSError):
                pass


def read_json_file(path: Path) -> Any:
    with path.open("r", encoding="utf-8-sig") as file:
        return json.load(file)


def first_nonempty(mapping: dict[str, Any], names: Iterable[str]) -> Any:
    for name in names:
        value = mapping.get(name)
        if value is not None and str(value).strip():
            return value
    return None


def parse_gallery_folder(metadata_path: Path) -> GalleryFolder:
    item = GalleryFolder(folder=metadata_path.parent, metadata_path=metadata_path)
    item.comicinfo_exists = (item.folder / COMICINFO_NAME).is_file()
    try:
        raw = read_json_file(metadata_path)
        if not isinstance(raw, dict):
            raise ValueError("metadata 顶层不是 JSON 对象")

        nested = raw.get("gallery")
        if isinstance(nested, dict):
            gallery = nested
            item.metadata_kind = "gallery"
        else:
            gallery = raw
            item.metadata_kind = "archive"

        gid_value = first_nonempty(gallery, ("gid", "galleryId", "galleryID"))
        token_value = first_nonempty(gallery, ("token", "galleryToken"))
        url_value = first_nonempty(gallery, ("galleryUrl", "galleryURL", "url"))
        title_value = first_nonempty(gallery, ("title", "rawTitle"))

        parsed_gid: int | None = None
        parsed_token: str | None = None
        parsed_url: str | None = None
        if url_value:
            match = GALLERY_URL_RE.search(str(url_value).strip())
            if match:
                parsed_gid = int(match.group(1))
                parsed_token = match.group(2).lower()
                parsed_url = match.group(0)

        if gid_value is not None:
            try:
                item.gid = int(gid_value)
            except (TypeError, ValueError) as exc:
                raise ValueError(f"gid 无效：{gid_value!r}") from exc
        else:
            item.gid = parsed_gid

        item.token = str(token_value).strip().lower() if token_value else parsed_token
        item.title = str(title_value).strip() if title_value else ""

        if item.gid is not None and item.token:
            # ExHentai 优先：metadata 中的 URL 主要用于校验 gid/token，生成时统一
            # 使用 ExHentai URL。联网阶段有 Cookie 时也会优先调用 ExHentai API。
            item.gallery_url = f"{DEFAULT_GALLERY_BASE_URL}/g/{item.gid}/{item.token}/"
        elif url_value:
            item.gallery_url = str(url_value).strip()

        if item.gid is None:
            item.scan_status = "invalid_metadata"
            item.message = "缺少有效 gid"
        elif not item.token:
            item.scan_status = "invalid_metadata"
            item.message = "缺少 token，且 galleryUrl 中无法提取 token"
        elif parsed_gid is not None and item.gid != parsed_gid:
            item.scan_status = "invalid_metadata"
            item.message = f"metadata gid ({item.gid}) 与 galleryUrl gid ({parsed_gid}) 不一致"
        elif token_value and parsed_token and item.token != parsed_token:
            item.scan_status = "invalid_metadata"
            item.message = "metadata token 与 galleryUrl token 不一致"
        else:
            item.scan_status = "ready"
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        item.scan_status = "invalid_metadata"
        item.message = str(exc)
    return item


def scan_root(root: Path) -> list[GalleryFolder]:
    items: list[GalleryFolder] = []
    report_dir = (root / REPORT_DIR_NAME).resolve()
    for current_dir, dir_names, file_names in os.walk(root):
        current = Path(current_dir)
        # 报告目录不是漫画目录，避免将来其中出现同名文件时被扫描。
        dir_names[:] = [name for name in dir_names if (current / name).resolve() != report_dir]
        metadata_names = [name for name in file_names if name.casefold() in METADATA_FILE_NAMES]
        if not metadata_names:
            continue

        candidates = [parse_gallery_folder(current / name) for name in metadata_names]
        # 正常情况下普通下载只有 metadata，Archive 下载只有 ametadata。若同一
        # 文件夹意外同时存在两者，优先采用能成功解析的文件，再根据目录名选择
        # Archive/ametadata 或普通/metadata，避免同一目录被处理两遍。
        valid_candidates = [candidate for candidate in candidates if candidate.scan_status == "ready"]
        selectable = valid_candidates or candidates
        archive_folder = current.name.casefold().startswith("archive")
        preferred_name = "ametadata" if archive_folder else "metadata"
        selectable.sort(
            key=lambda candidate: (
                candidate.metadata_path.name.casefold() != preferred_name,
                candidate.metadata_path.name.casefold(),
            )
        )
        selected = selectable[0]
        if len(candidates) > 1:
            note = f"同目录发现 metadata 和 ametadata；已采用 {selected.metadata_path.name}"
            selected.message = f"{selected.message}；{note}" if selected.message else note
        items.append(selected)
    items.sort(key=lambda item: (item.gid is None, item.gid or 0, str(item.folder).casefold()))
    return items


def comicinfo_is_valid(path: Path) -> bool:
    try:
        root = ET.parse(path).getroot()
        return root.tag == "ComicInfo" or root.tag.endswith("}ComicInfo")
    except (OSError, ET.ParseError):
        return False


def load_cookie_header(path: Path | None) -> str | None:
    if path is None:
        return None
    raw = read_json_file(path)
    cookies: dict[str, str] = {}
    if isinstance(raw, dict):
        source = raw.get("cookies", raw)
        if isinstance(source, dict):
            cookies = {str(key): str(value) for key, value in source.items() if value not in (None, "")}
        elif isinstance(source, list):
            for entry in source:
                if isinstance(entry, dict) and entry.get("name") and entry.get("value") is not None:
                    cookies[str(entry["name"])] = str(entry["value"])
    elif isinstance(raw, list):
        for entry in raw:
            if isinstance(entry, dict) and entry.get("name") and entry.get("value") is not None:
                cookies[str(entry["name"])] = str(entry["value"])
    if not cookies:
        raise ValueError("cookies.json 中没有找到有效 Cookie")
    return "; ".join(f"{name}={value}" for name, value in cookies.items())


def chunks(values: Sequence[tuple[int, str]], size: int) -> Iterable[Sequence[tuple[int, str]]]:
    for index in range(0, len(values), size):
        yield values[index : index + size]


def post_gdata(
    api_url: str,
    keys: Sequence[tuple[int, str]],
    cookie_header: str | None,
    timeout: float,
) -> dict[str, Any]:
    payload = json.dumps(
        {
            "method": "gdata",
            "gidlist": [[gid, token] for gid, token in keys],
            "namespace": 1,
        }
    ).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "JHenTai-ComicInfo-Recovery/1.0",
    }
    if cookie_header:
        headers["Cookie"] = cookie_header
    request = urllib.request.Request(api_url, data=payload, headers=headers, method="POST")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = response.read().decode("utf-8-sig")
    parsed = json.loads(body)
    if not isinstance(parsed, dict):
        raise ValueError("API 返回内容不是 JSON 对象")
    return parsed


def request_batch_with_retry(
    api_url: str,
    keys: Sequence[tuple[int, str]],
    cookie_header: str | None,
    timeout: float,
    retries: int,
) -> dict[str, Any]:
    waits = (2.0, 5.0, 10.0, 20.0)
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            return post_gdata(api_url, keys, cookie_header, timeout)
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
            last_error = exc
            if attempt >= retries:
                break
            wait = waits[min(attempt - 1, len(waits) - 1)]
            print(f"  请求失败（第 {attempt}/{retries} 次）：{exc}；{wait:g} 秒后重试……")
            time.sleep(wait)
    raise RuntimeError(f"请求在 {retries} 次尝试后仍失败：{last_error}") from last_error


def classify_api_error(message: str) -> str:
    lowered = message.casefold()
    if "copyright" in lowered or "dmca" in lowered:
        return "copyright_unavailable"
    if "removed" in lowered or "expunged" in lowered or "unavailable" in lowered or "not found" in lowered:
        return "removed_unavailable"
    if "token" in lowered:
        return "invalid_token"
    return "api_error"


def parse_api_response(response: dict[str, Any], requested: Sequence[tuple[int, str]]) -> ApiResult:
    result = ApiResult()
    raw_list = response.get("gmetadata")
    if not isinstance(raw_list, list):
        message = str(response.get("error") or "API 响应缺少 gmetadata")
        for key in requested:
            result.errors_by_key[key] = message
        return result

    for raw in raw_list:
        if not isinstance(raw, dict):
            continue
        try:
            gid = int(raw.get("gid"))
        except (TypeError, ValueError):
            continue
        token = str(raw.get("token") or "").strip().lower()
        key = (gid, token)
        # 某些错误项不回显 token，用本批中相同 gid 的 key 补齐。
        if not token:
            matches = [candidate for candidate in requested if candidate[0] == gid]
            if len(matches) == 1:
                key = matches[0]
        error = raw.get("error")
        if error:
            result.errors_by_key[key] = str(error)
        else:
            result.metadata_by_key[key] = raw

    for key in requested:
        if key not in result.metadata_by_key and key not in result.errors_by_key:
            # 如果 API 回传了同 gid、不同 token 的记录，也按 token 不匹配处理，不能误写。
            same_gid_errors = [message for candidate, message in result.errors_by_key.items() if candidate[0] == key[0]]
            result.errors_by_key[key] = same_gid_errors[0] if same_gid_errors else "API 未返回该 gid/token"
    return result


def request_batch_prefer_exhentai(
    keys: Sequence[tuple[int, str]],
    cookie_header: str | None,
    timeout: float,
    retries: int,
    api_url_override: str | None = None,
) -> ApiResult:
    """有 Cookie 时优先 ExHentai，只把未解决的条目回退到 EHentai。"""
    if api_url_override:
        api_urls = [api_url_override]
    elif cookie_header:
        api_urls = [EX_API_URL, EH_API_URL]
    else:
        api_urls = [EH_API_URL]

    combined = ApiResult()
    pending = list(keys)
    network_errors: list[str] = []
    for index, api_url in enumerate(api_urls):
        if not pending:
            break
        if index > 0:
            print(f"  {len(pending)} 个条目转用 EHentai API 回退查询……")
        try:
            response = request_batch_with_retry(api_url, pending, cookie_header, timeout, retries)
        except RuntimeError as exc:
            network_errors.append(f"{api_url}: {exc}")
            continue

        parsed = parse_api_response(response, pending)
        combined.metadata_by_key.update(parsed.metadata_by_key)
        for key in parsed.metadata_by_key:
            combined.errors_by_key.pop(key, None)
        for key, message in parsed.errors_by_key.items():
            if key not in combined.metadata_by_key:
                combined.errors_by_key[key] = message
        pending = [key for key in pending if key not in combined.metadata_by_key]

    if pending and network_errors and len(network_errors) == len(api_urls):
        raise RuntimeError("；".join(network_errors))
    for key in pending:
        combined.errors_by_key.setdefault(key, "ExHentai/EHentai API 均未返回该 gid/token")
    return combined


def split_tag(tag: Any) -> tuple[str, str]:
    text = str(tag).strip()
    if ":" in text:
        namespace, value = text.split(":", 1)
        return namespace, value
    return "temp", text


def add_text_element(parent: ET.Element, name: str, value: Any) -> None:
    element = ET.SubElement(parent, name)
    element.text = str(value)


def build_comicinfo(metadata: dict[str, Any], fallback_url: str) -> bytes:
    title = str(metadata.get("title") or "").strip()
    if not title:
        raise ValueError("API 元数据缺少 title")
    japanese_title = str(metadata.get("title_jpn") or "").strip()
    category = str(metadata.get("category") or "").strip()
    try:
        page_count = int(metadata.get("filecount"))
    except (TypeError, ValueError) as exc:
        raise ValueError("API 元数据 filecount 无效") from exc
    try:
        rating = float(metadata.get("rating"))
    except (TypeError, ValueError) as exc:
        raise ValueError("API 元数据 rating 无效") from exc

    raw_tags = metadata.get("tags") or []
    if not isinstance(raw_tags, list):
        raise ValueError("API 元数据 tags 不是列表")
    tags = [split_tag(tag) for tag in raw_tags if str(tag).strip()]
    artists = [value for namespace, value in tags if namespace == "artist"]
    characters = [value for namespace, value in tags if namespace == "character"]
    locations = [value for namespace, value in tags if namespace == "location"]
    languages = [value.casefold() for namespace, value in tags if namespace == "language" and value.casefold() != "translated"]
    language_iso = LANGUAGE_TO_ISO.get(languages[0]) if languages else None
    full_color = any(value.casefold() == "full color" for _, value in tags)

    gid = int(metadata.get("gid"))
    token = str(metadata.get("token") or "").strip()
    web = fallback_url
    if gid and token:
        web = f"{DEFAULT_GALLERY_BASE_URL}/g/{gid}/{token}/"

    root = ET.Element(
        "ComicInfo",
        {
            "xmlns:xsi": "http://www.w3.org/2001/XMLSchema-instance",
            "xmlns:xsn": "http://www.w3.org/2001/XMLSchema",
        },
    )
    add_text_element(root, "Title", title)
    add_text_element(root, "Series", title)
    if japanese_title:
        add_text_element(root, "AlternateSeries", japanese_title)
    if artists:
        joined_artists = ",".join(artists)
        add_text_element(root, "Writer", joined_artists)
        add_text_element(root, "Penciller", joined_artists)
    add_text_element(root, "Genre", category)
    add_text_element(root, "Tags", ",".join(f"{namespace}:{value}" for namespace, value in tags))
    add_text_element(root, "Web", web)
    add_text_element(root, "PageCount", page_count)
    if language_iso:
        add_text_element(root, "LanguageISO", language_iso)
    add_text_element(root, "BlackAndWhite", "No" if full_color else "Yes")
    add_text_element(root, "Manga", "Yes" if category == "Manga" else "No")
    if characters:
        add_text_element(root, "Characters", ",".join(characters))
    if locations:
        add_text_element(root, "Locations", ",".join(locations))
    add_text_element(root, "AgeRating", "Kids to Adults" if category == "Non-H" else "Adults Only 18+")
    add_text_element(root, "CommunityRating", f"{rating:.1f}")

    if hasattr(ET, "indent"):
        ET.indent(root, space="  ")
    return ET.tostring(root, encoding="utf-8", xml_declaration=True, short_empty_elements=True)


def write_comicinfo_atomic(folder: Path, content: bytes) -> None:
    target = folder / COMICINFO_NAME
    temporary = folder / f"{COMICINFO_NAME}.tmp"
    try:
        with temporary.open("wb") as file:
            file.write(content)
            file.flush()
            os.fsync(file.fileno())
        parsed = ET.parse(temporary).getroot()
        if parsed.tag != "ComicInfo" and not parsed.tag.endswith("}ComicInfo"):
            raise ValueError("生成的 XML 根节点不是 ComicInfo")
        os.replace(temporary, target)
    finally:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass


def relative_for_report(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def write_scan_report(root: Path, report_dir: Path, items: Sequence[GalleryFolder]) -> None:
    report_dir.mkdir(parents=True, exist_ok=True)
    with (report_dir / "comicinfo_scan_report.csv").open("w", encoding="utf-8-sig", newline="") as file:
        writer = csv.writer(file)
        # 报告不写 token，避免分享报告时泄露非公开画廊的访问令牌。
        writer.writerow(("gid", "元数据文件", "metadata类型", "扫描状态", "已有ComicInfo", "文件夹", "标题", "说明"))
        for item in items:
            writer.writerow(
                (
                    item.gid or "",
                    item.metadata_path.name,
                    item.metadata_kind,
                    item.scan_status,
                    "是" if item.comicinfo_exists else "否",
                    relative_for_report(item.folder, root),
                    item.title,
                    item.message,
                )
            )


def write_result_reports(root: Path, report_dir: Path, results: Sequence[Result]) -> None:
    headers = ("gid", "结果", "文件夹", "标题", "说明")
    groups = {
        "comicinfo_success.csv": [result for result in results if result.status == "success"],
        "comicinfo_failed.csv": [result for result in results if result.status not in {"success", "already_exists"}],
        "comicinfo_unavailable.csv": [
            result for result in results if result.status in {"copyright_unavailable", "removed_unavailable"}
        ],
    }
    for filename, selected in groups.items():
        with (report_dir / filename).open("w", encoding="utf-8-sig", newline="") as file:
            writer = csv.writer(file)
            writer.writerow(headers)
            for result in selected:
                item = result.folder
                writer.writerow(
                    (
                        item.gid or "",
                        result.status,
                        relative_for_report(item.folder, root),
                        item.title,
                        result.message,
                    )
                )


def write_summary(report_dir: Path, items: Sequence[GalleryFolder], results: Sequence[Result], scan_only: bool) -> None:
    scan_counts: dict[str, int] = {}
    for item in items:
        scan_counts[item.scan_status] = scan_counts.get(item.scan_status, 0) + 1
    result_counts: dict[str, int] = {}
    for result in results:
        result_counts[result.status] = result_counts.get(result.status, 0) + 1
    key_counts: dict[tuple[int, str], int] = {}
    for item in items:
        if item.key is not None:
            key_counts[item.key] = key_counts.get(item.key, 0) + 1
    summary = {
        "scanOnly": scan_only,
        "foldersFound": len(items),
        "uniqueGalleryKeys": len(key_counts),
        "duplicateGalleryKeys": sum(count > 1 for count in key_counts.values()),
        "existingComicInfo": sum(item.comicinfo_exists for item in items),
        "scanStatus": scan_counts,
        "resultStatus": result_counts,
    }
    with (report_dir / "comicinfo_summary.json").open("w", encoding="utf-8") as file:
        json.dump(summary, file, ensure_ascii=False, indent=2)


def process(args: argparse.Namespace) -> int:
    root = args.root.expanduser().resolve()
    if not root.is_dir():
        print(f"错误：根目录不存在或不是文件夹：{root}", file=sys.stderr)
        return 2

    report_dir = root / REPORT_DIR_NAME
    print(f"扫描目录：{root}")
    items = scan_root(root)
    write_scan_report(root, report_dir, items)
    ready = [item for item in items if item.scan_status == "ready"]
    invalid = [item for item in items if item.scan_status != "ready"]
    existing = [item for item in ready if item.comicinfo_exists and comicinfo_is_valid(item.folder / COMICINFO_NAME)]
    broken_existing = [item for item in ready if item.comicinfo_exists and item not in existing]

    print(f"找到 metadata/ametadata：{len(items)}")
    print(f"可处理：{len(ready)}；无效 metadata：{len(invalid)}")
    print(f"已有有效 ComicInfo.xml：{len(existing)}；已有但无效：{len(broken_existing)}")
    print(f"扫描报告：{report_dir / 'comicinfo_scan_report.csv'}")

    if args.scan_only:
        scan_results = [Result(item, "invalid_metadata", item.message) for item in invalid]
        write_summary(report_dir, items, scan_results, scan_only=True)
        print("已完成仅扫描模式；没有联网，也没有写入任何 ComicInfo.xml。")
        return 0 if items else 1

    try:
        cookie_header = load_cookie_header(args.cookies)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        print(f"错误：无法读取 Cookie：{exc}", file=sys.stderr)
        return 2

    results: list[Result] = [Result(item, "invalid_metadata", item.message) for item in invalid]
    targets: list[GalleryFolder] = []
    for item in ready:
        target = item.folder / COMICINFO_NAME
        if target.is_file() and comicinfo_is_valid(target) and not args.overwrite:
            results.append(Result(item, "already_exists", "已有有效 ComicInfo.xml，已跳过"))
        else:
            targets.append(item)

    folders_by_key: dict[tuple[int, str], list[GalleryFolder]] = {}
    for item in targets:
        assert item.key is not None
        folders_by_key.setdefault(item.key, []).append(item)
    unique_keys = list(folders_by_key)
    batch_list = list(chunks(unique_keys, args.batch_size))
    print(f"需要联网查询：{len(unique_keys)} 个唯一画廊，写入 {len(targets)} 个文件夹，共 {len(batch_list)} 批。")

    for batch_number, batch in enumerate(batch_list, start=1):
        print(f"[{batch_number}/{len(batch_list)}] 查询 {len(batch)} 个画廊……")
        try:
            api_result = request_batch_prefer_exhentai(
                batch,
                cookie_header,
                args.timeout,
                args.retries,
                args.api_url,
            )
        except RuntimeError as exc:
            for key in batch:
                for item in folders_by_key[key]:
                    results.append(Result(item, "network_error", str(exc)))
            print(f"  本批失败：{exc}")
        else:
            for key in batch:
                folders = folders_by_key[key]
                metadata = api_result.metadata_by_key.get(key)
                if metadata is None:
                    message = api_result.errors_by_key.get(key, "API 未返回该画廊")
                    status = classify_api_error(message)
                    for item in folders:
                        results.append(Result(item, status, message))
                    continue

                if bool(metadata.get("expunged")):
                    # expunged 画廊仍可能返回完整元数据，因此可以正常生成；在说明中记录状态。
                    expunged_note = "API 标记为 expunged；已根据返回的完整元数据生成"
                else:
                    expunged_note = ""
                for item in folders:
                    try:
                        content = build_comicinfo(
                            metadata,
                            item.gallery_url or f"{DEFAULT_GALLERY_BASE_URL}/g/{key[0]}/{key[1]}/",
                        )
                        write_comicinfo_atomic(item.folder, content)
                        results.append(Result(item, "success", expunged_note))
                    except (OSError, ValueError, ET.ParseError) as exc:
                        results.append(Result(item, "write_error", str(exc)))
            batch_success = sum(
                1
                for result in results
                if result.status == "success" and result.folder.key in batch
            )
            print(f"  本批已写入：{batch_success}")

        if batch_number < len(batch_list) and args.interval:
            time.sleep(args.interval)

    write_result_reports(root, report_dir, results)
    write_summary(report_dir, items, results, scan_only=False)
    counts: dict[str, int] = {}
    for result in results:
        counts[result.status] = counts.get(result.status, 0) + 1

    print("\n处理完成：")
    for status, count in sorted(counts.items()):
        print(f"  {status}: {count}")
    print(f"报告目录：{report_dir}")
    return 0 if not any(result.status not in {"success", "already_exists"} for result in results) else 1


def main(argv: Sequence[str] | None = None) -> int:
    configure_windows_console()
    return process(parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main())
