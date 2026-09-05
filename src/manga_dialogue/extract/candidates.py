"""仮名の候補リスト。台帳に載せる前の無名人物を保持し、再登場で台帳に昇格させる。

抽出結果の話者文字列は候補の段階から「〜（仮）」で、台帳との違いはプロンプト上の扱いだけ。
昇格しても出力の書き換えは不要。
"""

import json
from datetime import datetime, timezone
from pathlib import Path

from pydantic import BaseModel, Field

from manga_dialogue.models import Character

PROMOTE_AFTER_PAGES = 2


class PageRef(BaseModel):
    volume: int
    page: int


class Candidate(BaseModel):
    name: str
    appearance: str = ""
    seen: list[PageRef] = Field(default_factory=list)
    created_at: str = ""

    def page_count(self) -> int:
        return len({(p.volume, p.page) for p in self.seen})

    def to_character(self) -> Character:
        return Character(name=self.name, appearance=self.appearance)


class CandidateStore:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.items: dict[str, Candidate] = {}

    @classmethod
    def load(cls, path: Path) -> "CandidateStore":
        store = cls(path)
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8"))
            for raw in data.get("candidates", []):
                c = Candidate.model_validate(raw)
                store.items[c.name] = c
        return store

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        data = {"candidates": [c.model_dump() for c in self.items.values()]}
        self.path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def get(self, name: str) -> Candidate | None:
        return self.items.get(name)

    def note(self, name: str, volume: int, page: int, appearance: str = "") -> Candidate:
        """候補を登録、または再登場を記録する。外見は空のときだけ埋める"""
        c = self.items.get(name)
        if c is None:
            c = Candidate(name=name, appearance=appearance, created_at=datetime.now(timezone.utc).isoformat(timespec="seconds"))
            self.items[name] = c
        elif appearance and not c.appearance:
            c.appearance = appearance
        if not any(p.volume == volume and p.page == page for p in c.seen):
            c.seen.append(PageRef(volume=volume, page=page))
        return c

    def remove(self, name: str) -> Candidate | None:
        return self.items.pop(name, None)

    def promotable(self) -> list[Candidate]:
        return [c for c in self.items.values() if c.page_count() >= PROMOTE_AFTER_PAGES]

    def to_prompt_text(self) -> str:
        if not self.items:
            return ""
        return "\n".join(f"- {c.name}: {c.appearance}" for c in self.items.values())


def is_provisional(name: str) -> bool:
    return name.endswith("（仮）")
