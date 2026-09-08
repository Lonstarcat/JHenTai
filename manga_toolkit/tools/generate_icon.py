from __future__ import annotations

from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = PROJECT_ROOT / "Emangato.png"
DEFAULT_DESTINATION = PROJECT_ROOT / "Emangato.ico"
ICON_SIZES = (16, 24, 32, 48, 64, 128, 256)


def generate_icon(
    source: Path = DEFAULT_SOURCE,
    destination: Path = DEFAULT_DESTINATION,
) -> Path:
    if not source.is_file():
        raise FileNotFoundError(f"图标源文件不存在：{source}")
    try:
        with Image.open(source) as opened:
            image = opened.convert("RGBA")
    except OSError as error:
        raise ValueError(f"无法读取 PNG 图标：{source}") from error

    side = max(image.size)
    if image.size != (side, side):
        square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        square.alpha_composite(image, ((side - image.width) // 2, (side - image.height) // 2))
        image = square

    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(
        destination,
        format="ICO",
        sizes=[(size, size) for size in ICON_SIZES],
        bitmap_format="png",
    )
    return destination


if __name__ == "__main__":
    output = generate_icon()
    print(f"已生成应用图标：{output}")
