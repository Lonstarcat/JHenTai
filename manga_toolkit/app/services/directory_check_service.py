from __future__ import annotations

import os
import zipfile
from pathlib import Path

from app.models.gallery_folder import GalleryFolder, GalleryStorage
from app.models.toolkit_features import DirectoryIssue


class DirectoryCheckService:
    IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif"}
    ALLOWED_FILES = {"metadata", "ametadata", "comicinfo.xml"}

    def check(self, galleries: list[GalleryFolder]) -> list[DirectoryIssue]:
        issues: list[DirectoryIssue] = []
        for gallery in galleries:
            if gallery.storage_type is GalleryStorage.CBZ:
                issues.extend(self._check_cbz(gallery))
                continue
            try:
                entries = list(os.scandir(gallery.path))
            except OSError as error:
                issues.append(DirectoryIssue(gallery.gallery_id, gallery.path, gallery.path, "读取失败", str(error)))
                continue
            image_count = 0
            for entry in entries:
                path = Path(entry.path)
                if entry.is_dir(follow_symlinks=False):
                    issues.append(DirectoryIssue(gallery.gallery_id, gallery.path, path, "子文件夹", "漫画目录仅允许一级文件"))
                elif path.suffix.casefold() in self.IMAGE_EXTENSIONS:
                    image_count += 1
                elif entry.name.casefold() not in self.ALLOWED_FILES:
                    issues.append(DirectoryIssue(gallery.gallery_id, gallery.path, path, "异常文件", path.suffix or "无扩展名"))
            if image_count == 0:
                issues.append(DirectoryIssue(gallery.gallery_id, gallery.path, gallery.path, "缺少图片", "未找到支持的图片格式"))
        return issues

    def _check_cbz(self, gallery: GalleryFolder) -> list[DirectoryIssue]:
        issues: list[DirectoryIssue] = []
        image_count = 0
        try:
            with zipfile.ZipFile(gallery.path) as archive:
                bad = archive.testzip()
                if bad:
                    return [DirectoryIssue(gallery.gallery_id, gallery.path, gallery.path, "损坏 CBZ", f"损坏成员：{bad}")]
                for info in archive.infolist():
                    if info.is_dir():
                        continue
                    normalized = info.filename.replace("\\", "/").removeprefix("./")
                    item = Path(normalized)
                    if "/" in normalized:
                        issues.append(DirectoryIssue(gallery.gallery_id, gallery.path, gallery.path, "CBZ 结构错误", normalized))
                    if item.suffix.casefold() in self.IMAGE_EXTENSIONS:
                        image_count += 1
                    elif item.name.casefold() not in self.ALLOWED_FILES:
                        issues.append(DirectoryIssue(gallery.gallery_id, gallery.path, gallery.path, "CBZ 异常文件", normalized))
        except (OSError, zipfile.BadZipFile) as error:
            return [DirectoryIssue(gallery.gallery_id, gallery.path, gallery.path, "损坏 CBZ", str(error))]
        if image_count == 0:
            issues.append(DirectoryIssue(gallery.gallery_id, gallery.path, gallery.path, "缺少图片", "CBZ 内未找到支持的图片格式"))
        return issues
