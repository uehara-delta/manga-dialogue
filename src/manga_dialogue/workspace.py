from pathlib import Path

DEFAULT_ROOT = Path("works")


class Work:
    """作品と巻のディレクトリ構成を一元管理する。

    works/<title>/
        characters.json          作品全体で共有するキャラ台帳
        pending_renames.jsonl    保留中の改名候補
        volumes/<NN>/
            captures/NNNN.png
            output/NNNN.json
    """

    def __init__(self, title: str, root: Path = DEFAULT_ROOT, volume: int = 1) -> None:
        self.title = title
        self.root = root
        self.volume = volume
        self.dir = root / title

    @property
    def characters_path(self) -> Path:
        return self.dir / "characters.json"

    @property
    def pending_renames_path(self) -> Path:
        return self.dir / "pending_renames.jsonl"

    @property
    def volumes_dir(self) -> Path:
        return self.dir / "volumes"

    @property
    def volume_dir(self) -> Path:
        return self.volumes_dir / f"{self.volume:02d}"

    @property
    def captures_dir(self) -> Path:
        return self.volume_dir / "captures"

    @property
    def output_dir(self) -> Path:
        return self.volume_dir / "output"

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

    def all_volumes(self) -> list["Work"]:
        """この作品に存在する巻を番号順に返す"""
        if not self.volumes_dir.exists():
            return []
        nums = sorted(int(p.name) for p in self.volumes_dir.iterdir() if p.is_dir() and p.name.isdigit())
        return [Work(self.title, self.root, n) for n in nums]
