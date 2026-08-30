import json
from pathlib import Path

from manga_dialogue.models import Character


class CharacterBook:
    """作品ごとのキャラ台帳。characters.json を読み書きする。"""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.characters: list[Character] = []

    @classmethod
    def load(cls, path: Path) -> "CharacterBook":
        book = cls(path)
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8"))
            book.characters = [Character.model_validate(c) for c in data.get("characters", [])]
        return book

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        data = {"characters": [c.model_dump() for c in self.characters]}
        self.path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def _known_names(self) -> set[str]:
        names: set[str] = set()
        for c in self.characters:
            names.add(c.name)
            names.update(c.aliases)
        return names

    def merge(self, new_characters: list[Character]) -> list[Character]:
        """台帳にない名前のキャラのみ追加し、追加分を返す"""
        known = self._known_names()
        added: list[Character] = []
        for c in new_characters:
            name = c.name.strip()
            if not name or name in known or name in ("不明", "ナレーション"):
                continue
            self.characters.append(c)
            known.add(name)
            known.update(c.aliases)
            added.append(c)
        return added

    def to_prompt_text(self) -> str:
        if not self.characters:
            return "（まだ登録されていません）"
        lines = []
        for c in self.characters:
            alias = f"（別名: {', '.join(c.aliases)}）" if c.aliases else ""
            lines.append(f"- {c.name}{alias}: {c.appearance}")
        return "\n".join(lines)
