import base64
import time
from pathlib import Path

import anthropic
from pydantic import ValidationError

from manga_dialogue.extract.characters import CharacterBook
from manga_dialogue.extract.prompt import SYSTEM_PROMPT, build_user_prompt
from manga_dialogue.models import PageExtraction, cap_context_confidence, normalize_text, sort_reading_order

DEFAULT_MODEL = "claude-opus-5"
MAX_ATTEMPTS = 3

MEDIA_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp"}


class ExtractionRefused(RuntimeError):
    pass


class ExtractionFailed(RuntimeError):
    """リトライしても有効な構造化出力が得られなかった"""


def extract_page(
    client: anthropic.Anthropic,
    image_path: Path,
    book: CharacterBook,
    model: str = DEFAULT_MODEL,
    final_book: bool = False,
) -> PageExtraction:
    """画像1枚を Anthropic API に送り、セリフと新キャラを構造化して返す

    final_book=True のときは処理済み範囲を反映した台帳であることをプロンプトで伝え、
    「不明」を減らすよう促す。モデル出力が壊れた JSON だった場合は数回リトライする。
    """
    last_error: Exception | None = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            return _request(client, image_path, book, model, final_book)
        except (ValidationError, ValueError) as e:
            last_error = e
            if attempt < MAX_ATTEMPTS:
                time.sleep(2 * attempt)
    raise ExtractionFailed(f"{image_path.name}: {MAX_ATTEMPTS} 回試行しても出力を解析できませんでした") from last_error


def _request(
    client: anthropic.Anthropic,
    image_path: Path,
    book: CharacterBook,
    model: str,
    final_book: bool,
) -> PageExtraction:
    data = base64.standard_b64encode(image_path.read_bytes()).decode("ascii")
    media_type = MEDIA_TYPES[image_path.suffix.lower()]

    response = client.messages.parse(
        model=model,
        max_tokens=8000,
        system=[{"type": "text", "text": SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}}],
        messages=[
            {
                "role": "user",
                "content": [
                    {"type": "image", "source": {"type": "base64", "media_type": media_type, "data": data}},
                    {"type": "text", "text": build_user_prompt(book.to_prompt_text(), final_book=final_book)},
                ],
            }
        ],
        output_format=PageExtraction,
    )
    if response.stop_reason == "refusal":
        raise ExtractionRefused(f"{image_path.name}: モデルが処理を拒否しました")
    if response.parsed_output is None:
        raise ValueError(f"{image_path.name}: 構造化出力を取得できませんでした (stop_reason={response.stop_reason})")
    extraction = response.parsed_output
    extraction.lines = normalize_text(cap_context_confidence(sort_reading_order(extraction.lines, extraction.panels)))
    return extraction
