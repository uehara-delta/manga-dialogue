import json
from pathlib import Path

from manga_dialogue.extract.characters import CharacterBook
from manga_dialogue.models import PageResult, Rename
from manga_dialogue.workspace import Work


def apply_rename(work: Work, book: CharacterBook, from_name: str, to_name: str) -> int:
    """台帳を改名し、出力済み JSON の speaker を書き換える。書き換えたセリフ数を返す"""
    if from_name == to_name:
        return 0
    from manga_dialogue.extract.candidates import CandidateStore
    from manga_dialogue.models import Character

    candidates = CandidateStore.load(work.candidates_path)
    candidate = candidates.remove(from_name)
    if candidate is not None:
        candidates.save()
    if not book.rename(from_name, to_name) and candidate is not None and book.find(to_name) is None:
        # 候補のまま本名が判明した: 候補の外見を引き継いで台帳に登録する
        book.characters.append(Character(name=to_name, aliases=[from_name], appearance=candidate.appearance))
    elif candidate is not None:
        target = book.find(to_name)
        if target is not None:
            if from_name not in target.aliases and from_name != target.name:
                target.aliases.append(from_name)
            if not target.appearance:
                target.appearance = candidate.appearance
    book.save()
    changed = 0
    for out in _all_output_files(work):
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


def _all_output_files(work: Work) -> list[Path]:
    return [f for v in work.all_volumes() for f in v.output_files()]


def record_pending(work: Work, page: int, rename: Rename) -> Path:
    """閾値未満で自動適用しなかった改名候補を保留として記録する（同じ組は 1 件に集約）"""
    from manga_dialogue.extract.pending import PendingStore

    store = PendingStore.load(work.pending_renames_path)
    store.upsert(rename, volume=work.volume, page=page)
    return work.pending_renames_path
