"""保留中の改名候補の状態管理。

pending_renames.jsonl は候補ごとに 1 行（from→to の組で一意）。
- id: from→to から決まる短いハッシュ
- status: pending / approved / rejected
- sources: 提案の履歴 [{volume, page, confidence, reason, at}]
- confidence: sources の最大値
旧形式（1 提案 1 行、id なし）は読み込み時に同じ組ごとにまとめて変換する。
"""

import hashlib
import json
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path

from manga_dialogue.models import Rename

STATUSES = ("pending", "approved", "rejected")


@dataclass
class PendingSource:
    volume: int
    page: int
    confidence: float
    reason: str
    at: str


@dataclass
class PendingRename:
    id: str
    from_name: str
    to_name: str
    status: str
    confidence: float
    sources: list[PendingSource] = field(default_factory=list)
    updated_at: str = ""

    @property
    def reason(self) -> str:
        """最も確信度の高い提案の根拠"""
        return max(self.sources, key=lambda s: s.confidence).reason if self.sources else ""

    def to_dict(self) -> dict:
        return asdict(self)


def make_id(from_name: str, to_name: str) -> str:
    return hashlib.sha1(f"{from_name}→{to_name}".encode()).hexdigest()[:10]


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class PendingStore:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.items: dict[str, PendingRename] = {}

    @classmethod
    def load(cls, path: Path) -> "PendingStore":
        store = cls(path)
        if not path.exists():
            return store
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            raw = json.loads(line)
            if "id" in raw and "status" in raw:
                item = PendingRename(
                    id=raw["id"], from_name=raw["from_name"], to_name=raw["to_name"], status=raw["status"],
                    confidence=float(raw.get("confidence", 0.0)),
                    sources=[PendingSource(**s) for s in raw.get("sources", [])],
                    updated_at=raw.get("updated_at", ""),
                )
                store.items[item.id] = item
            else:
                store.upsert(
                    Rename(from_name=raw["from_name"], to_name=raw["to_name"], confidence=float(raw.get("confidence", 0.0)), reason=raw.get("reason", "")),
                    volume=int(raw.get("volume", 1)), page=int(raw.get("page", 0)), at=raw.get("at", ""),
                    save=False,
                )
        return store

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        lines = [json.dumps(item.to_dict(), ensure_ascii=False) for item in self.items.values()]
        self.path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")

    def upsert(self, rename: Rename, volume: int, page: int, at: str | None = None, save: bool = True) -> PendingRename:
        """候補を追加、または同じ組の候補に根拠を追記する。却下済み・承認済みの状態は変えない"""
        item_id = make_id(rename.from_name, rename.to_name)
        source = PendingSource(volume=volume, page=page, confidence=rename.confidence, reason=rename.reason, at=at or _now())
        item = self.items.get(item_id)
        if item is None:
            item = PendingRename(id=item_id, from_name=rename.from_name, to_name=rename.to_name, status="pending", confidence=rename.confidence)
            self.items[item_id] = item
        item.sources.append(source)
        item.confidence = max(item.confidence, rename.confidence)
        item.updated_at = source.at
        if save:
            self.save()
        return item

    def list(self, status: str | None = "pending") -> list[PendingRename]:
        items = [i for i in self.items.values() if status is None or i.status == status]
        return sorted(items, key=lambda i: (-i.confidence, i.from_name))

    def get(self, item_id: str) -> PendingRename | None:
        return self.items.get(item_id)

    def set_status(self, item_id: str, status: str) -> PendingRename:
        if status not in STATUSES:
            raise ValueError(f"不正な状態: {status}")
        item = self.items[item_id]
        item.status = status
        item.updated_at = _now()
        self.save()
        return item
