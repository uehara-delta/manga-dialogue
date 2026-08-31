# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec: manga-dialogue エンジン（CLI）を onedir でビルドする。

uv run --group dev pyinstaller packaging/engine.spec
出力: dist/manga-dialogue-engine/manga-dialogue-engine(.exe)
"""
import sys

from PyInstaller.utils.hooks import collect_submodules, copy_metadata

hiddenimports = [
    *collect_submodules("manga_dialogue"),
    *collect_submodules("google.genai"),
    *collect_submodules("anthropic"),
]
if sys.platform == "darwin":
    hiddenimports += ["Quartz", "AppKit"]

datas = [
    *copy_metadata("manga-dialogue"),
    *copy_metadata("google-genai"),
    *copy_metadata("anthropic"),
]

a = Analysis(
    ["../src/manga_dialogue/__main__.py"],
    pathex=["../src"],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    runtime_hooks=[],
    excludes=["tkinter", "matplotlib", "IPython", "jupyter"],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="manga-dialogue-engine",
    debug=False,
    strip=False,
    upx=False,
    console=True,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="manga-dialogue-engine",
)
