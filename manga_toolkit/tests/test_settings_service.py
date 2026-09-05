import json
from pathlib import Path

from app.services.settings_service import AppSettings, SettingsService


def test_theme_mode_round_trip(tmp_path: Path) -> None:
    service = SettingsService(tmp_path / "settings.json")
    service.save(AppSettings(theme_mode="dark"))
    assert service.load().theme_mode == "dark"


def test_monochrome_theme_mode_round_trip(tmp_path: Path) -> None:
    service = SettingsService(tmp_path / "settings.json")
    service.save(AppSettings(theme_mode="monochrome"))
    assert service.load().theme_mode == "monochrome"


def test_invalid_theme_mode_falls_back_to_system(tmp_path: Path) -> None:
    path = tmp_path / "settings.json"
    path.write_text(json.dumps({"theme_mode": "unsupported"}), encoding="utf-8")
    assert SettingsService(path).load().theme_mode == "system"
