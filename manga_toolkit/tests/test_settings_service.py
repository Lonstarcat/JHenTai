import json
from pathlib import Path

from app.services.settings_service import AppSettings, SettingsService
from app.core.paths import AppPaths


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


def test_czkawka_path_round_trip(tmp_path: Path) -> None:
    service = SettingsService(tmp_path / "settings.json")
    service.save(AppSettings(czkawka_path=r"C:\Tools\czkawka_gui.exe"))
    assert service.load().czkawka_path == r"C:\Tools\czkawka_gui.exe"


def test_app_paths_copy_legacy_data_without_deleting_source(tmp_path: Path) -> None:
    legacy = tmp_path / "MangaLibraryToolkit"
    current = tmp_path / "Emangato"
    legacy.mkdir()
    (legacy / "settings.json").write_text('{"theme_mode":"dark"}', encoding="utf-8")
    paths = AppPaths(
        current,
        current / "logs",
        current / "reports",
        current / "app.db",
        current / "settings.json",
        legacy,
    )
    paths.ensure_directories()
    assert paths.settings_path.read_text(encoding="utf-8") == '{"theme_mode":"dark"}'
    assert (legacy / "settings.json").exists()
