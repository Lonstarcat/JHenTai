from __future__ import annotations

import sys
from pathlib import Path


def resource_candidates(relative_path: str | Path) -> tuple[Path, ...]:
    """Return bundled-resource candidates in frozen and source layouts."""
    relative = Path(relative_path)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"Resource path must be relative: {relative}")

    roots: list[Path] = []
    bundle_root = getattr(sys, "_MEIPASS", None)
    if bundle_root:
        roots.append(Path(bundle_root))
    roots.append(Path(__file__).resolve().parents[2])
    return tuple(root / relative for root in roots)


def bundled_resource(relative_path: str | Path) -> Path:
    """Resolve a read-only application resource without using data paths."""
    candidates = resource_candidates(relative_path)
    return next((candidate for candidate in candidates if candidate.is_file()), candidates[0])
