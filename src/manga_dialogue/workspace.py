import json
import os
import shutil
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_ROOT = Path("works")
DEFAULT_RUN = "default"


class RunLocked(RuntimeError):
    """別のプロセスがこの run を書き換え中"""


class Work:
    """作品・run・巻のディレクトリ構成を一元管理する。

    works/<title>/
        volumes/<NN>/captures/NNNN.png     キャプチャ（run 間で共有）
        runs/<run>/
            characters.json                run ごとのキャラ台帳
            pending_renames.jsonl          保留中の改名候補
            volumes/<NN>/output/NNNN.json  抽出結果

    run はモデルやプロンプトの違いごとに結果を分けて保持するための単位。
    """

    def __init__(self, title: str, root: Path = DEFAULT_ROOT, volume: int = 1, run: str = DEFAULT_RUN) -> None:
        self.title = title
        self.root = root
        self.volume = volume
        self.run = run
        self.dir = root / title

    @property
    def run_dir(self) -> Path:
        return self.dir / "runs" / self.run

    @property
    def characters_path(self) -> Path:
        return self.run_dir / "characters.json"

    @property
    def pending_renames_path(self) -> Path:
        return self.run_dir / "pending_renames.jsonl"

    @property
    def candidates_path(self) -> Path:
        return self.run_dir / "candidates.json"

    @property
    def lock_path(self) -> Path:
        return self.run_dir / ".lock"

    def current_lock(self) -> dict | None:
        """有効なロックがあればその内容を返す。プロセスが消えている古いロックは無視する"""
        if not self.lock_path.exists():
            return None
        try:
            info = json.loads(self.lock_path.read_text(encoding="utf-8"))
            os.kill(int(info["pid"]), 0)
        except (ValueError, KeyError, ProcessLookupError, PermissionError):
            return None
        return info

    @contextmanager
    def locked(self, command: str):
        """run を書き換える処理の間だけロックファイルを置く"""
        held = self.current_lock()
        if held is not None:
            raise RunLocked(f"run '{self.run}' は実行中です（{held.get('command')}, pid {held.get('pid')}）")
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.lock_path.write_text(
            json.dumps({"pid": os.getpid(), "command": command, "started_at": datetime.now(timezone.utc).isoformat(timespec="seconds")}),
            encoding="utf-8",
        )
        try:
            yield
        finally:
            self.lock_path.unlink(missing_ok=True)

    @property
    def volumes_dir(self) -> Path:
        return self.dir / "volumes"

    @property
    def captures_dir(self) -> Path:
        return self.volumes_dir / f"{self.volume:02d}" / "captures"

    @property
    def output_dir(self) -> Path:
        return self.run_dir / "volumes" / f"{self.volume:02d}" / "output"

    def capture_path(self, page: int) -> Path:
        return self.captures_dir / f"{page:04d}.png"

    def output_path(self, page: int) -> Path:
        return self.output_dir / f"{page:04d}.json"

    def capture_images(self) -> list[Path]:
        return sorted(self.captures_dir.glob("*.png"))

    def output_files(self) -> list[Path]:
        return sorted(self.output_dir.glob("*.json"))

    def ensure_dirs(self) -> None:
        self.captures_dir.mkdir(parents=True, exist_ok=True)
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def with_volume(self, volume: int) -> "Work":
        return Work(self.title, self.root, volume, self.run)

    def all_volumes(self) -> list["Work"]:
        """この作品に存在する巻（キャプチャがある巻）を番号順に返す"""
        if not self.volumes_dir.exists():
            return []
        nums = sorted(int(p.name) for p in self.volumes_dir.iterdir() if p.is_dir() and p.name.isdigit())
        return [self.with_volume(n) for n in nums]

    def all_runs(self) -> list[str]:
        runs_dir = self.dir / "runs"
        if not runs_dir.exists():
            return []
        return sorted(p.name for p in runs_dir.iterdir() if p.is_dir())

    def init_run_from(self, source_run: str) -> None:
        """別 run の台帳をコピーして、この run を開始する"""
        src = Work(self.title, self.root, self.volume, source_run)
        self.run_dir.mkdir(parents=True, exist_ok=True)
        if src.characters_path.exists() and not self.characters_path.exists():
            shutil.copy(src.characters_path, self.characters_path)
