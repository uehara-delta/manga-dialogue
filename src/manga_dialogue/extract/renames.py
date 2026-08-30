import json
from datetime import datetime, timezone
from pathlib import Path

from manga_dialogue.extract.characters import CharacterBook
from manga_dialogue.models import PageResult, Rename
from manga_dialogue.workspace import Work


def apply_rename(work: Work, book: CharacterBook, from_name: str, to_name: str) -> int:
    """台帳を改名し、出力済み JSON の speaker を書き換える。書き換えたセリフ数を返す"""
    book.rename(from_name, to_name)
    book.save()
    changed = 0
    for out in sorted(work.output_dir.glob("*.json")):
        result = PageResult.model_validate_json(out.read_text(encoding="utf-8"))
        touched = False
        for line in result.lines:
            if line.speaker == from_name:
                line.speaker = to_name
            elif line.speaker.startswith(from_name + "（"):
                line.speaker = to_name + line.speaker[len(from_name):]
            else:
                continue
            changed += 1
            touched = True
        if touched:
            out.write_text(json.dumps(result.model_dump(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return changed


def record_pending(work: Work, page: int, rename: Rename) -> Path:
    """閾値未満で自動適用しなかった改名候補を追記する"""
    path = work.dir / "pending_renames.jsonl"
    entry = {
        "page": page,
        "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        **rename.model_dump(),
    }
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    return path
