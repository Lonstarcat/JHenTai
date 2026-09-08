# -*- mode: python ; coding: utf-8 -*-

from pathlib import Path

from PyInstaller.utils.hooks import collect_submodules


project_root = Path(SPECPATH)
icon_path = project_root / "Emangato.ico"
if not icon_path.is_file():
    raise FileNotFoundError("Emangato.ico 不存在，请先运行 python tools/generate_icon.py")
datas = [
    (str(style_path), "app/ui/styles")
    for style_path in sorted((project_root / "app/ui/styles").glob("*.qss"))
]
datas.extend(
    [
        (str(project_root / "Emangato.png"), "."),
    ]
)
hiddenimports = collect_submodules("keyring.backends")

analysis = Analysis(
    ["main.py"],
    pathex=[],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(analysis.pure)
exe = EXE(
    pyz,
    analysis.scripts,
    [],
    exclude_binaries=True,
    name="Emangato",
    icon=str(icon_path),
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
)
collection = COLLECT(
    exe,
    analysis.binaries,
    analysis.datas,
    strip=False,
    upx=True,
    name="Emangato",
)
