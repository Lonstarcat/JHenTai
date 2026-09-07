from __future__ import annotations

import json
import os
import shutil
import tempfile
from datetime import UTC, datetime
import unicodedata
import zipfile
from pathlib import Path

from app.models.gallery_folder import GalleryFolder, GalleryStorage, GalleryType
from app.models.toolkit_features import MetadataIssue
from app.services.name_organizer_service import folder_title


class MetadataService:
    FILES = ("metadata", "ametadata")

    def analyze(self, galleries: list[GalleryFolder]) -> list[MetadataIssue]:
        issues: list[MetadataIssue] = []
        for gallery in galleries:
            expected = folder_title(gallery.folder_name)
            if gallery.storage_type is GalleryStorage.CBZ:
                issues.extend(self._analyze_cbz(gallery, expected))
                continue
            for file_name in self._expected_files(gallery):
                path = gallery.path / file_name
                if not path.is_file():
                    issues.append(MetadataIssue(gallery.path, file_name, "缺失", folder_title=expected))
                    continue
                try:
                    data = json.loads(path.read_text(encoding="utf-8-sig"))
                    title = self._title(data, file_name)
                    group = self._group_name(data, file_name)
                    status, detail = self._classify_title(title, expected)
                    issues.append(MetadataIssue(gallery.path, file_name, status, title, expected, group, detail))
                except (OSError, UnicodeError, json.JSONDecodeError, TypeError) as error:
                    issues.append(MetadataIssue(gallery.path, file_name, "解析失败", folder_title=expected, detail=str(error)))
        return issues

    def _analyze_cbz(self, gallery: GalleryFolder, expected: str) -> list[MetadataIssue]:
        issues: list[MetadataIssue] = []
        try:
            with zipfile.ZipFile(gallery.path) as archive:
                members = {
                    info.filename.replace("\\", "/").removeprefix("./").casefold(): info
                    for info in archive.infolist()
                    if not info.is_dir()
                    and "/" not in info.filename.replace("\\", "/").removeprefix("./")
                }
                for file_name in self._expected_files(gallery):
                    info = members.get(file_name)
                    if info is None:
                        issues.append(MetadataIssue(gallery.path, file_name, "缺失", folder_title=expected, detail="CBZ 内部（只读）"))
                        continue
                    try:
                        data = json.loads(archive.read(info).decode("utf-8-sig"))
                        title = self._title(data, file_name)
                        group = self._group_name(data, file_name)
                        status, detail = self._classify_title(title, expected)
                        issues.append(MetadataIssue(gallery.path, file_name, status, title, expected, group, f"CBZ 内部（只读）{(' · ' + detail) if detail else ''}"))
                    except (UnicodeError, json.JSONDecodeError, TypeError, OSError) as error:
                        issues.append(MetadataIssue(gallery.path, file_name, "解析失败", folder_title=expected, detail=f"CBZ 内部（只读） · {error}"))
        except (OSError, zipfile.BadZipFile) as error:
            for file_name in self._expected_files(gallery):
                issues.append(MetadataIssue(gallery.path, file_name, "解析失败", folder_title=expected, detail=f"损坏 CBZ · {error}"))
        return issues

    @staticmethod
    def _expected_files(gallery: GalleryFolder) -> tuple[str, ...]:
        if gallery.gallery_type is GalleryType.NORMAL:
            return ("metadata",)
        if gallery.gallery_type is GalleryType.ARCHIVE:
            return ("ametadata",)
        return MetadataService.FILES

    def update_group_name(
        self,
        folder: Path,
        file_name: str,
        value: str,
        backup_root: Path,
    ) -> Path:
        if file_name not in self.FILES:
            raise ValueError(f"不支持的 metadata 文件：{file_name}")
        path = folder / file_name
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        backup = backup_root / folder.name / file_name
        backup.parent.mkdir(parents=True, exist_ok=True)
        if backup.exists():
            timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S%fZ")
            backup = backup.with_name(f"{file_name}.{timestamp}.bak")
        shutil.copy2(path, backup)
        if file_name == "metadata":
            gallery = data.get("gallery")
            if not isinstance(gallery, dict):
                raise ValueError("metadata.gallery 不是对象")
            gallery["groupName"] = value
        else:
            if not isinstance(data, dict):
                raise ValueError("ametadata 不是对象")
            data["groupName"] = value
        self._atomic_json_write(path, data)
        return backup

    def backup_files(
        self,
        folder: Path,
        backup_root: Path,
        *,
        include_comic_info: bool = False,
    ) -> list[Path]:
        """Back up existing metadata files without touching image content."""
        names = [*self.FILES]
        if include_comic_info:
            names.append("ComicInfo.xml")
        backups: list[Path] = []
        for file_name in names:
            source = folder / file_name
            if not source.is_file():
                continue
            destination = backup_root / folder.name / file_name
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.exists():
                timestamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S%fZ")
                destination = destination.with_name(f"{file_name}.{timestamp}.bak")
            shutil.copy2(source, destination)
            backups.append(destination)
        return backups

    @staticmethod
    def _title(data: object, file_name: str) -> str:
        if not isinstance(data, dict):
            return ""
        if file_name == "metadata":
            gallery = data.get("gallery")
            return str(gallery.get("title", "")) if isinstance(gallery, dict) else ""
        return str(data.get("title", ""))

    @staticmethod
    def _group_name(data: object, file_name: str) -> str:
        if not isinstance(data, dict):
            return ""
        if file_name == "metadata":
            gallery = data.get("gallery")
            return str(gallery.get("groupName", "")) if isinstance(gallery, dict) else ""
        return str(data.get("groupName", ""))

    @staticmethod
    def _equivalent(left: str, right: str) -> bool:
        normalize = lambda value: unicodedata.normalize("NFKC", value).replace(":", "").replace("：", "").replace(" ", "").casefold()
        return bool(left) and normalize(left) == normalize(right)

    @staticmethod
    def _classify_title(actual: str, expected: str) -> tuple[str, str]:
        if actual == expected:
            return "正常", ""
        if not actual:
            return "文本缺失", "Metadata 中没有 title"
        if unicodedata.normalize("NFC", actual) == unicodedata.normalize("NFC", expected):
            return "Unicode 差异", "NFC 标准化后相同"
        if actual.replace(" ", "") == expected.replace(" ", ""):
            return "空格差异", "忽略普通空格后相同"
        without_colon = lambda value: value.replace(":", "").replace("：", "").replace(" ", "")
        if without_colon(actual) == without_colon(expected):
            return "冒号差异", "忽略全角/半角冒号和空格后相同"
        without_exclamation = lambda value: value.replace("!", "").replace("！", "").replace(" ", "")
        if without_exclamation(actual) == without_exclamation(expected):
            return "感叹号差异", "忽略全角/半角感叹号和空格后相同"
        if unicodedata.normalize("NFKC", actual) == unicodedata.normalize("NFKC", expected):
            return "全角半角差异", "NFKC 标准化后相同"
        normalized_actual = unicodedata.normalize("NFKC", actual).casefold()
        normalized_expected = unicodedata.normalize("NFKC", expected).casefold()
        if normalized_actual.startswith(normalized_expected) or normalized_expected.startswith(normalized_actual):
            return "文本截断", "一侧标题是另一侧的前缀"
        index = MetadataService._first_difference(actual, expected)
        actual_part = actual[index : index + 16] or "<结束>"
        expected_part = expected[index : index + 16] or "<结束>"
        return "标题不一致", f"第 {index + 1} 个字符起不同：Metadata={actual_part!r}，文件夹={expected_part!r}"

    @staticmethod
    def _first_difference(left: str, right: str) -> int:
        for index, (left_char, right_char) in enumerate(zip(left, right)):
            if left_char != right_char:
                return index
        return min(len(left), len(right))

    @staticmethod
    def _atomic_json_write(path: Path, data: object) -> None:
        descriptor, name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
        temporary = Path(name)
        try:
            with open(descriptor, "w", encoding="utf-8", closefd=True) as stream:
                json.dump(data, stream, ensure_ascii=False, separators=(",", ":"))
                stream.flush()
                os.fsync(stream.fileno())
            temporary.replace(path)
        except Exception:
            temporary.unlink(missing_ok=True)
            raise
