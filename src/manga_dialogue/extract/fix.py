import json

from pydantic import BaseModel, Field

from manga_dialogue.extract.characters import CharacterBook
from manga_dialogue.extract.extractor import load_image_part
from manga_dialogue.extract.llm import Part, TextPart, VisionModel
from manga_dialogue.models import PageResult
from manga_dialogue.workspace import Work

FIX_SYSTEM_PROMPT = """\
あなたは漫画のセリフ書き起こしデータを修正する編集者です。
抽出済みのセリフ（巻・ページ・行番号・コマ・話者・本文）とキャラ台帳、そして修正の指示を渡します。
指示に従って修正すべき行だけを changes として返してください。

- 変更しない行は含めないでください。
- 各 change には volume・page・index（そのページ内の行番号）を正確に入れ、変更するフィールド
  （speaker / text / panel）だけを指定してください。
- reason には根拠を簡潔に書いてください。
- 指示の範囲を超えた修正はしないでください。判断に迷う場合は変更しません。
"""

class LineChange(BaseModel):
    volume: int
    page: int
    index: int = Field(description="ページ内の行番号（0 始まり）")
    speaker: str | None = None
    text: str | None = None
    panel: int | None = None
    reason: str = ""


class FixPlan(BaseModel):
    changes: list[LineChange] = Field(default_factory=list)


def load_pages(work: Work, volume: int | None, pages: list[int]) -> list[tuple[Work, PageResult]]:
    volumes = [work.with_volume(volume)] if volume is not None else work.all_volumes()
    results: list[tuple[Work, PageResult]] = []
    for vol in volumes:
        for out in vol.output_files():
            result = PageResult.model_validate_json(out.read_text(encoding="utf-8"))
            if pages and result.page not in pages:
                continue
            results.append((vol, result))
    return results


def _dialogue_block(targets: list[tuple[Work, PageResult]]) -> str:
    lines = []
    for vol, result in targets:
        for i, l in enumerate(result.lines):
            lines.append(f"v{result.volume:02d} p{result.page:03d} #{i} panel{l.panel} [{l.speaker}] {l.text}")
    return "\n".join(lines)


def propose_fix(
    llm: VisionModel,
    book: CharacterBook,
    targets: list[tuple[Work, PageResult]],
    instruction: str,
    with_images: bool = False,
) -> FixPlan:
    """指示に基づく修正案をモデルに作らせる。with_images で対象ページの画像も添付する"""
    text = f"""\
## キャラ台帳
{book.to_prompt_text()}

## 抽出済みセリフ（巻 ページ #行番号 コマ [話者] 本文）
{_dialogue_block(targets)}

## 修正の指示
{instruction}
"""
    parts: list[Part] = []
    if with_images:
        for vol, result in targets:
            parts.append(TextPart(f"（{result.volume}巻 p{result.page:03d} の画像）"))
            parts.append(load_image_part(vol.capture_path(result.page)))
    parts.append(TextPart(text))
    return llm.complete(FIX_SYSTEM_PROMPT, parts, FixPlan, max_tokens=32000)


def apply_changes(work: Work, changes: list[LineChange]) -> int:
    """変更案を出力 JSON に適用し、変更した行に manual を付ける。適用件数を返す"""
    by_page: dict[tuple[int, int], list[LineChange]] = {}
    for c in changes:
        by_page.setdefault((c.volume, c.page), []).append(c)
    applied = 0
    for (volume, page), items in by_page.items():
        vol = work.with_volume(volume)
        path = vol.output_path(page)
        if not path.exists():
            continue
        result = PageResult.model_validate_json(path.read_text(encoding="utf-8"))
        for c in items:
            if not 0 <= c.index < len(result.lines):
                continue
            line = result.lines[c.index]
            if c.speaker is not None:
                line.speaker = c.speaker
            if c.text is not None:
                line.text = c.text
            if c.panel is not None:
                line.panel = c.panel
            line.manual = True
            applied += 1
        path.write_text(json.dumps(result.model_dump(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return applied
