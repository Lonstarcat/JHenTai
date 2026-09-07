from __future__ import annotations

import json
import logging
import os
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path

logger = logging.getLogger(__name__)


@dataclass(slots=True)
class AppSettings:
    library_path: str = ""
    seven_zip_path: str = ""
    ffmpeg_path: str = ""
    ffprobe_path: str = ""
    czkawka_path: str = ""
    safety_mode: bool = True
    gallery_site: str = "exhentai"
    status_batch_size: int = 25
    status_request_interval: float = 1.0
    status_pause_every_batches: int = 4
    status_pause_seconds: float = 5.0
    status_retries: int = 2
    status_cache_hours: int = 24
    theme_mode: str = "system"


class SettingsService:
    def __init__(self, settings_path: Path) -> None:
        self._settings_path = settings_path

    def load(self) -> AppSettings:
        if not self._settings_path.exists():
            return AppSettings()
        try:
            data = json.loads(self._settings_path.read_text(encoding="utf-8"))
            gallery_site = str(data.get("gallery_site", "exhentai"))
            if gallery_site not in {"e-hentai", "exhentai"}:
                gallery_site = "exhentai"
            theme_mode = str(data.get("theme_mode", "system"))
            if theme_mode not in {"system", "light", "dark", "monochrome"}:
                theme_mode = "system"
            return AppSettings(
                library_path=str(data.get("library_path", "")),
                seven_zip_path=str(data.get("seven_zip_path", "")),
                ffmpeg_path=str(data.get("ffmpeg_path", "")),
                ffprobe_path=str(data.get("ffprobe_path", "")),
                czkawka_path=str(data.get("czkawka_path", "")),
                safety_mode=bool(data.get("safety_mode", True)),
                gallery_site=gallery_site,
                status_batch_size=min(25, max(1, int(data.get("status_batch_size", 25)))),
                status_request_interval=max(0.0, float(data.get("status_request_interval", 1.0))),
                status_pause_every_batches=max(1, int(data.get("status_pause_every_batches", 4))),
                status_pause_seconds=max(0.0, float(data.get("status_pause_seconds", 5.0))),
                status_retries=max(0, int(data.get("status_retries", 2))),
                status_cache_hours=max(1, int(data.get("status_cache_hours", 24))),
                theme_mode=theme_mode,
            )
        except (OSError, ValueError, TypeError) as error:
            logger.exception("Unable to read settings: %s", error)
            return AppSettings()

    def save(self, settings: AppSettings) -> None:
        self._settings_path.parent.mkdir(parents=True, exist_ok=True)
        payload = json.dumps(asdict(settings), ensure_ascii=False, indent=2)
        descriptor, temporary_name = tempfile.mkstemp(
            prefix="settings_",
            suffix=".tmp",
            dir=self._settings_path.parent,
        )
        temporary_path = Path(temporary_name)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
            temporary_path.replace(self._settings_path)
        except OSError:
            temporary_path.unlink(missing_ok=True)
            raise
