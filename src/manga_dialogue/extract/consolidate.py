import json

from pydantic import BaseModel, Field

from manga_dialogue.extract.characters import CharacterBook
from manga_dialogue.extract.llm import TextPart, VisionModel
from manga_dialogue.models import PageResult, Rename
from manga_dialogue.workspace import Work

CONSOLIDATE_SYSTEM_PROMPT = """\
あなたは漫画のセリフ書き起こしデータを整理する編集者です。
1ページずつ独立に抽出されたセリフ（複数巻にまたがることがあります）と、その過程で作られたキャラ台帳を渡します。
台帳には、名前が分からなかった時点で付けた「（仮）」付きの仮名が残っています。

## やること
全ページのセリフを通して読み、以下を見つけて renames として返してください。
1. 仮名の人物の本名が、他のセリフから分かる場合（名前で呼ばれている、名乗っている、
   第三者が指し示している、など）。from_name に仮名、to_name に本名。
2. 同一人物が台帳に二重に載っている場合（仮名と実名、あるいは仮名同士）。
   from_name に消す側、to_name に残す側。実名があれば実名を残します。
3. 外見の記述や会話の流れから、仮名の人物が台帳の実名の人物と同一と判断できる場合。

## 判断の基準
- reason には根拠となるページ番号と該当セリフを必ず引用してください。
- 名指し・名乗りなど根拠が明確なら confidence 0.85 以上、状況からの推測なら 0.5〜0.7、
  それ以下の推測は返さないでください。
- 兵士・群衆など、最後まで名前が出ない人物は無理に統合しないでください。
- 別人を統合するミスは、統合し損ねるより害が大きいことを念頭に置いてください。
- to_name には「（仮）」を付けません。また「〜ちゃん」「〜さん」などの愛称・敬称ではなく、
  台帳に載っている正式な名前（載っていなければ呼び名から敬称を除いたもの）にしてください。
"""


class ConsolidationPlan(BaseModel):
    renames: list[Rename] = Field(default_factory=list)


def build_dialogue_text(work: Work) -> str:
    """全巻の出力を「v巻 pページ [話者] セリフ」の行に整形する"""
    lines: list[str] = []
    for vol in work.all_volumes():
        for out in vol.output_files():
            result = PageResult.model_validate_json(out.read_text(encoding="utf-8"))
            for line in result.lines:
                lines.append(f"v{vol.volume:02d} p{result.page:03d} [{line.speaker}] {line.text}")
    return "\n".join(lines)


def propose_consolidation(llm: VisionModel, book: CharacterBook, work: Work) -> ConsolidationPlan:
    """台帳と全セリフから、仮名の解決と重複統合の案をモデルに作らせる"""
    book_json = json.dumps(
        {"characters": [c.model_dump() for c in book.characters]}, ensure_ascii=False, indent=1
    )
    user = f"""\
## キャラ台帳
{book_json}

## 全セリフ（巻 ページ [話者] セリフ）
{build_dialogue_text(work)}

台帳を整理するための renames を返してください。
"""
    return llm.complete(CONSOLIDATE_SYSTEM_PROMPT, [TextPart(user)], ConsolidationPlan, max_tokens=64000)
