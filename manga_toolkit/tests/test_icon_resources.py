from __future__ import annotations

from pathlib import Path

from PIL import Image

from tools.generate_icon import ICON_SIZES, generate_icon


def test_runtime_png_is_valid() -> None:
    root = Path(__file__).resolve().parents[1]
    with Image.open(root / "Emangato.png") as image:
        image.verify()
        assert image.width >= 256
        assert image.height >= 256


def test_generate_multisize_windows_icon(tmp_path: Path) -> None:
    root = Path(__file__).resolve().parents[1]
    destination = tmp_path / "Emangato.ico"
    generate_icon(root / "Emangato.png", destination)
    assert destination.is_file()
    with Image.open(destination) as icon:
        assert {(size, size) for size in ICON_SIZES}.issubset(icon.ico.sizes())


def test_icon_generation_is_reproducible(tmp_path: Path) -> None:
    root = Path(__file__).resolve().parents[1]
    first = tmp_path / "first.ico"
    second = tmp_path / "second.ico"
    generate_icon(root / "Emangato.png", first)
    generate_icon(root / "Emangato.png", second)
    assert first.read_bytes() == second.read_bytes()


def test_pyinstaller_spec_uses_generated_icon() -> None:
    root = Path(__file__).resolve().parents[1]
    spec = (root / "Emangato.spec").read_text(encoding="utf-8")
    assert 'icon=str(icon_path)' in spec
    assert 'tools/generate_icon.py' in spec
