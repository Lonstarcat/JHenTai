from __future__ import annotations

import sys
from pathlib import Path

import pytest

from app.core.resources import bundled_resource, resource_candidates


@pytest.mark.parametrize("theme", ("light", "dark", "monochrome"))
def test_source_theme_resources_are_non_empty(theme: str) -> None:
    path = bundled_resource(f"app/ui/styles/{theme}.qss")
    assert path.is_file()
    assert path.read_text(encoding="utf-8").strip()


def test_frozen_bundle_resource_takes_priority(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    bundled = tmp_path / "app/ui/styles/dark.qss"
    bundled.parent.mkdir(parents=True)
    bundled.write_text("QWidget { background: black; }", encoding="utf-8")
    monkeypatch.setattr(sys, "_MEIPASS", str(tmp_path), raising=False)

    assert resource_candidates("app/ui/styles/dark.qss")[0] == bundled
    assert bundled_resource("app/ui/styles/dark.qss") == bundled


def test_resource_path_rejects_parent_traversal() -> None:
    with pytest.raises(ValueError):
        bundled_resource("../settings.json")


def test_pyinstaller_spec_explicitly_packages_qss_files() -> None:
    spec = Path(__file__).resolve().parents[1] / "Emangato.spec"
    text = spec.read_text(encoding="utf-8")
    assert '"app/ui/styles"' in text
    assert 'glob("*.qss")' in text
