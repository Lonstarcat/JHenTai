from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class AppPaths:
    data_dir: Path
    log_dir: Path
    report_dir: Path
    database_path: Path
    settings_path: Path

    @classmethod
    def create(cls) -> "AppPaths":
        override = os.environ.get("MANGA_TOOLKIT_DATA_DIR")
        if override:
            data_dir = Path(override).expanduser()
        elif os.name == "nt" and os.environ.get("LOCALAPPDATA"):
            data_dir = Path(os.environ["LOCALAPPDATA"]) / "MangaLibraryToolkit"
        else:
            data_dir = Path.home() / ".manga_library_toolkit"

        return cls(
            data_dir=data_dir,
            log_dir=data_dir / "logs",
            report_dir=data_dir / "reports",
            database_path=data_dir / "app.db",
            settings_path=data_dir / "settings.json",
        )

    def ensure_directories(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.report_dir.mkdir(parents=True, exist_ok=True)
