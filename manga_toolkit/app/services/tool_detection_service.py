from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class ToolInfo:
    name: str
    found: bool
    path: Path | None
    version: str
    error: str = ""


class ToolDetectionService:
    _CANDIDATES: dict[str, tuple[str, ...]] = {
        "7-Zip": ("7z.exe", "7zz.exe", "7z", "7zz"),
        "FFmpeg": ("ffmpeg.exe", "ffmpeg"),
        "FFprobe": ("ffprobe.exe", "ffprobe"),
    }

    def detect(self, configured_paths: dict[str, str] | None = None) -> list[ToolInfo]:
        configured_paths = configured_paths or {}
        return [
            self._detect_one(name, configured_paths.get(name, ""))
            for name in self._CANDIDATES
        ]

    def _detect_one(self, name: str, configured_path: str) -> ToolInfo:
        executable: Path | None = None
        if configured_path:
            candidate = Path(configured_path).expanduser()
            if candidate.is_file():
                executable = candidate

        if executable is None:
            for candidate_name in self._CANDIDATES[name]:
                resolved = shutil.which(candidate_name)
                if resolved:
                    executable = Path(resolved)
                    break

        if executable is None:
            return ToolInfo(name=name, found=False, path=None, version="未找到")

        try:
            command = [str(executable)]
            command.extend(["--version"] if name != "7-Zip" else ["i"])
            creation_flags = (
                subprocess.CREATE_NO_WINDOW
                if os.name == "nt" and hasattr(subprocess, "CREATE_NO_WINDOW")
                else 0
            )
            process = subprocess.run(
                command,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=5,
                check=False,
                creationflags=creation_flags,
            )
            output = (process.stdout or process.stderr).strip().splitlines()
            version = output[0].strip() if output else "已找到"
            return ToolInfo(name, True, executable, version)
        except (OSError, subprocess.SubprocessError) as error:
            return ToolInfo(name, True, executable, "版本读取失败", str(error))
