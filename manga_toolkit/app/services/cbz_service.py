from __future__ import annotations

import subprocess
import shutil
from datetime import UTC, datetime
from uuid import uuid4
import zipfile
from pathlib import Path

from app.models.gallery_folder import GalleryFolder
from app.models.toolkit_features import CbzCheckResult, CbzStatus, ExistingCbzPolicy
from app.services.directory_check_service import DirectoryCheckService


class CbzService:
    def build_command(self, seven_zip: Path, folder: Path, destination: Path, compression: int = 0) -> list[str]:
        return [str(seven_zip), "a", "-tzip", f"-mx={compression}", "-y", str(destination), "."]

    def pack(self, seven_zip: Path, folder: Path, destination: Path, compression: int = 0) -> None:
        if destination.exists():
            raise FileExistsError(f"目标已存在：{destination}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        process = subprocess.run(
            self.build_command(seven_zip, folder, destination, compression),
            cwd=folder,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        if process.returncode != 0:
            destination.unlink(missing_ok=True)
            raise RuntimeError(process.stderr.strip() or process.stdout.strip() or f"7-Zip 退出码 {process.returncode}")

    def pack_with_policy(
        self,
        seven_zip: Path,
        gallery: GalleryFolder,
        destination: Path,
        compression: int,
        policy: ExistingCbzPolicy,
        backup_root: Path,
    ) -> tuple[str, Path | None]:
        """Pack one item and preserve an existing archive before replacement."""
        if destination.exists():
            if policy is ExistingCbzPolicy.SKIP:
                return "skipped", None
            if policy is ExistingCbzPolicy.VERIFY and self.check(gallery, destination).status is CbzStatus.VALID:
                return "verified", None
        temporary = destination.with_name(f".{destination.stem}.{uuid4().hex}.tmp.cbz")
        self.pack(seven_zip, gallery.path, temporary, compression)
        backup: Path | None = None
        try:
            if destination.exists():
                backup_root.mkdir(parents=True, exist_ok=True)
                backup = backup_root / destination.name
                if backup.exists():
                    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S%fZ")
                    backup = backup.with_name(f"{destination.stem}.{stamp}{destination.suffix}")
                shutil.move(str(destination), str(backup))
            temporary.replace(destination)
        except Exception:
            temporary.unlink(missing_ok=True)
            if backup is not None and backup.exists() and not destination.exists():
                shutil.move(str(backup), str(destination))
            raise
        return "rebuilt" if backup is not None else "created", backup

    def check(self, gallery: GalleryFolder, cbz_path: Path) -> CbzCheckResult:
        if not cbz_path.is_file():
            return CbzCheckResult(gallery.path, cbz_path, CbzStatus.MISSING, gallery.file_count, 0)
        try:
            with zipfile.ZipFile(cbz_path) as archive:
                bad = archive.testzip()
                if bad:
                    return CbzCheckResult(gallery.path, cbz_path, CbzStatus.DAMAGED, gallery.file_count, len(archive.infolist()), bad)
                names = [info.filename for info in archive.infolist() if not info.is_dir()]
        except (OSError, zipfile.BadZipFile) as error:
            return CbzCheckResult(gallery.path, cbz_path, CbzStatus.DAMAGED, gallery.file_count, 0, str(error))
        count = len(names)
        if not names:
            return CbzCheckResult(gallery.path, cbz_path, CbzStatus.EMPTY, gallery.file_count, count)
        if any("/" in name.strip("/") for name in names):
            return CbzCheckResult(gallery.path, cbz_path, CbzStatus.NESTED_ROOT, gallery.file_count, count)
        lower = {Path(name).name.casefold() for name in names}
        images = [name for name in names if Path(name).suffix.casefold() in DirectoryCheckService.IMAGE_EXTENSIONS]
        if not images:
            return CbzCheckResult(gallery.path, cbz_path, CbzStatus.NO_IMAGE, gallery.file_count, count)
        if not ({"metadata", "ametadata"} & lower):
            return CbzCheckResult(gallery.path, cbz_path, CbzStatus.NO_METADATA, gallery.file_count, count)
        if "comicinfo.xml" not in lower:
            return CbzCheckResult(gallery.path, cbz_path, CbzStatus.NO_COMIC_INFO, gallery.file_count, count)
        if count != gallery.file_count:
            return CbzCheckResult(gallery.path, cbz_path, CbzStatus.COUNT_MISMATCH, gallery.file_count, count)
        return CbzCheckResult(gallery.path, cbz_path, CbzStatus.VALID, gallery.file_count, count)
