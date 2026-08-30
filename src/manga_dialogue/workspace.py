from pathlib import Path

DEFAULT_ROOT = Path("works")


class Work:
    """作品ごとのディレクトリ構成を一元管理する。

    works/<title>/
        characters.json
        captures/NNNN.png
        output/NNNN.json
    """

    def __init__(self, title: str, root: Path = DEFAULT_ROOT) -> None:
        self.title = title
        self.dir = root / title

    @property
    def captures_dir(self) -> Path:
        return self.dir / "captures"

    @property
    def output_dir(self) -> Path:
        return self.dir / "output"

    @property
    def characters_path(self) -> Path:
        return self.dir / "characters.json"

    def capture_path(self, page: int) -> Path:
        return self.captures_dir / f"{page:04d}.png"

    def output_path(self, page: int) -> Path:
        return self.output_dir / f"{page:04d}.json"

    def capture_images(self) -> list[Path]:
        return sorted(self.captures_dir.glob("*.png"))

    def ensure_dirs(self) -> None:
        self.captures_dir.mkdir(parents=True, exist_ok=True)
        self.output_dir.mkdir(parents=True, exist_ok=True)
