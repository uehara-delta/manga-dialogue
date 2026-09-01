import csv
import io
from pathlib import Path

from manga_dialogue.models import PageResult
from manga_dialogue.workspace import Work

COLUMNS = ["volume", "page", "panel", "speaker", "text", "confidence", "basis", "manual"]
FORMATS = {"csv": ".csv", "tsv": ".tsv", "markdown": ".md"}


def collect_rows(work: Work, volume: int | None = None) -> list[dict]:
    """作品（または指定巻）の全セリフを読み順に平坦化する"""
    volumes = [work.with_volume(volume)] if volume is not None else work.all_volumes()
    rows: list[dict] = []
    for vol in volumes:
        for out in vol.output_files():
            result = PageResult.model_validate_json(out.read_text(encoding="utf-8"))
            for line in result.lines:
                rows.append(
                    {
                        "volume": result.volume,
                        "page": result.page,
                        "panel": line.panel,
                        "speaker": line.speaker,
                        "text": line.text,
                        "confidence": line.confidence,
                        "basis": line.basis or "",
                        "manual": line.manual or result.manual,
                    }
                )
    return rows


def render(rows: list[dict], fmt: str, title: str) -> str:
    if fmt in ("csv", "tsv"):
        buf = io.StringIO()
        writer = csv.DictWriter(buf, fieldnames=COLUMNS, delimiter="," if fmt == "csv" else "\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
        return buf.getvalue()
    if fmt == "markdown":
        out = [f"# {title}"]
        current: tuple[int, int] | None = None
        for r in rows:
            key = (r["volume"], r["page"])
            if key != current:
                out += ["", f"## {r['volume']}巻 p{r['page']:03d}", ""]
                current = key
            out.append(f"- **{r['speaker']}**: {r['text']}")
        return "\n".join(out) + "\n"
    raise ValueError(f"未対応の形式: {fmt}")


def export(work: Work, fmt: str, dest: Path | None = None, volume: int | None = None, excel: bool = True) -> tuple[Path, int]:
    """書き出したファイルパスと行数を返す。

    excel=True のとき CSV / TSV は BOM 付き UTF-8 で書く（Excel がそのまま開ける）。
    Markdown は常に BOM なし。
    """
    rows = collect_rows(work, volume)
    suffix = FORMATS[fmt]
    if dest is None:
        name = work.title if volume is None else f"{work.title}_{volume:02d}"
        dest = work.dir / f"{name}{suffix}"
    dest.parent.mkdir(parents=True, exist_ok=True)
    encoding = "utf-8-sig" if excel and fmt in ("csv", "tsv") else "utf-8"
    dest.write_text(render(rows, fmt, work.title), encoding=encoding)
    return dest, len(rows)
