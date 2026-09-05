"""台帳の外見を、その人物が実際に話しているページの画像から検証・書き直す。

初出ページでの登録ミス（別人の外見を書いてしまう、2 人の外見が入れ替わる）を後から直すための手段。
人物ごとに、尻尾判定かつ confidence の高いセリフを含むページを選び、画像とそのセリフを渡して
「この名前の人物」の外見を記述させる。
"""

from dataclasses import dataclass
from pathlib import Path

from pydantic import BaseModel, Field

from manga_dialogue.extract.characters import CharacterBook
from manga_dialogue.extract.extractor import load_image_part
from manga_dialogue.extract.llm import Part, TextPart, VisionModel
from manga_dialogue.models import PageResult
from manga_dialogue.workspace import Work

VERIFY_SYSTEM_PROMPT = """\
あなたは漫画の登場人物の外見を記録する編集者です。画像は漫画のページで、指定した人物が話している
セリフと、その吹き出しの位置（画像全体に対する割合、x は左端から、y は上端から）を示します。
その吹き出しの尻尾が指す人物を見て、後のページでも同一人物だと照合できる恒常的な特徴
（性別・年齢層・髪型・髪色・服装・持ち物・傷や装飾など）を 1〜2 文で記述してください。
その場の姿勢・表情・場所は書きません。複数の画像で別人を指しているように見える場合は
confidence を下げ、note にその旨を書いてください。
"""

MAX_PAGES_PER_CHARACTER = 2


class AppearanceVerification(BaseModel):
    appearance: str = Field(description="恒常的な特徴の記述")
    confidence: float = Field(ge=0.0, le=1.0, description="示されたセリフの発話者を正しく特定できた確信度")
    note: str = Field(default="", description="矛盾や不確かさがあれば")


@dataclass
class Evidence:
    work: Work
    result: PageResult
    lines: list  # この人物のセリフ（Line）


def collect_evidence(work: Work, name: str, max_pages: int = MAX_PAGES_PER_CHARACTER) -> list[Evidence]:
    """尻尾判定のセリフが多く confidence が高いページから順に、その人物の証拠ページを選ぶ"""
    scored: list[tuple[float, Evidence]] = []
    for vol in work.all_volumes():
        for out in vol.output_files():
            result = PageResult.model_validate_json(out.read_text(encoding="utf-8"))
            lines = [l for l in result.lines if l.speaker == name and l.basis == "tail"]
            if not lines:
                continue
            score = sum(l.confidence for l in lines)
            scored.append((score, Evidence(vol, result, lines)))
    scored.sort(key=lambda t: -t[0])
    return [e for _, e in scored[:max_pages]]


def verify_character(llm: VisionModel, name: str, evidence: list[Evidence]) -> AppearanceVerification:
    parts: list[Part] = []
    for i, e in enumerate(evidence, 1):
        parts.append(TextPart(f"（画像 {i}: {e.result.volume}巻 p{e.result.page:03d}）"))
        parts.append(load_image_part(e.work.capture_path(e.result.page)))
        quotes = "\n".join(
            f"- 「{l.text}」 (x={l.x:.2f}, y={l.y:.2f})" if l.x is not None and l.y is not None else f"- 「{l.text}」"
            for l in e.lines
        )
        parts.append(TextPart(f"画像 {i} で「{name}」が話しているセリフ:\n{quotes}"))
    parts.append(TextPart(f"「{name}」の外見を記述してください。"))
    return llm.complete(VERIFY_SYSTEM_PROMPT, parts, AppearanceVerification, max_tokens=4000)


def select_targets(book: CharacterBook, counts: dict[str, int], names: list[str], top: int, min_lines: int) -> list[str]:
    """検証対象の名前。指定があればそれ、なければセリフ数上位の実名キャラ"""
    if names:
        return [n for n in names if book.find(n) is not None]
    ranked = sorted(
        (c.name for c in book.characters if not c.name.endswith("（仮）") and counts.get(c.name, 0) >= min_lines),
        key=lambda n: -counts.get(n, 0),
    )
    return ranked[:top]
