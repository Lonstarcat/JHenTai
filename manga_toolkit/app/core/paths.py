from __future__ import annotations

import os
import shutil
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class AppPaths:
    data_dir: Path
    log_dir: Path
    report_dir: Path
    database_path: Path
    settings_path: Path
    legacy_data_dir: Path | None = None

    @classmethod
    def create(cls) -> "AppPaths":
        override = os.environ.get("EMANGATO_DATA_DIR") or os.environ.get("MANGA_TOOLKIT_DATA_DIR")
        legacy_data_dir: Path | None = None
        if override:
            data_dir = Path(override).expanduser()
        elif os.name == "nt" and os.environ.get("LOCALAPPDATA"):
            base = Path(os.environ["LOCALAPPDATA"])
            data_dir = base / "Emangato"
            legacy_data_dir = base / "MangaLibraryToolkit"
        else:
            data_dir = Path.home() / ".emangato"
            legacy_data_dir = Path.home() / ".manga_library_toolkit"

        return cls(
            data_dir=data_dir,
            log_dir=data_dir / "logs",
            report_dir=data_dir / "reports",
            database_path=data_dir / "app.db",
            settings_path=data_dir / "settings.json",
            legacy_data_dir=legacy_data_dir,
        )

    def ensure_directories(self) -> None:
        if (
            not self.data_dir.exists()
            and self.legacy_data_dir is not None
            and self.legacy_data_dir.is_dir()
        ):
            shutil.copytree(self.legacy_data_dir, self.data_dir, copy_function=shutil.copy2)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.report_dir.mkdir(parents=True, exist_ok=True)
