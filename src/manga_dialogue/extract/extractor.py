import base64
import io
import time
from pathlib import Path

import anthropic
from PIL import Image
from pydantic import ValidationError

from manga_dialogue.extract.characters import CharacterBook
from manga_dialogue.extract.prompt import SYSTEM_PROMPT, build_user_prompt
from manga_dialogue.models import PageExtraction, cap_context_confidence, normalize_text, sort_reading_order

DEFAULT_MODEL = "claude-opus-5"
MAX_ATTEMPTS = 3
MAX_API_ATTEMPTS = 5
API_BACKOFF_SECONDS = 30
TRANSIENT_API_ERRORS = (
    anthropic.RateLimitError,
    anthropic.InternalServerError,
    anthropic.OverloadedError,
    anthropic.APIConnectionError,
    anthropic.APITimeoutError,
)
SPREAD_ASPECT = 1.15


def is_spread(image_path: Path) -> bool:
    """横長の画像（縦横比が SPREAD_ASPECT 超）を見開きとみなす"""
    with Image.open(image_path) as img:
        w, h = img.size
    return w / h > SPREAD_ASPECT

MAX_LONG_EDGE = 2576
MAX_IMAGE_BYTES = 4_500_000


def encode_image(image_path: Path) -> tuple[str, str]:
    """API に送る画像を用意し、(media_type, base64) を返す。

    長辺が MAX_LONG_EDGE を超える場合は縮小する（API 側でそれ以上は縮小されるため）。
    PNG がサイズ上限を超える場合は JPEG にする。
    """
    with Image.open(image_path) as src:
        img = src.convert("RGB")
    long_edge = max(img.size)
    if long_edge > MAX_LONG_EDGE:
        scale = MAX_LONG_EDGE / long_edge
        img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    media_type = "image/png"
    if buf.tell() > MAX_IMAGE_BYTES:
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=92)
        media_type = "image/jpeg"
    return media_type, base64.standard_b64encode(buf.getvalue()).decode("ascii")


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
    parse_failures = api_failures = 0
    while parse_failures < MAX_ATTEMPTS and api_failures < MAX_API_ATTEMPTS:
        try:
            return _request(client, image_path, book, model, final_book)
        except (ValidationError, ValueError) as e:
            last_error = e
            parse_failures += 1
            time.sleep(2 * parse_failures)
        except TRANSIENT_API_ERRORS as e:
            last_error = e
            api_failures += 1
            time.sleep(API_BACKOFF_SECONDS * api_failures)
    raise ExtractionFailed(
        f"{image_path.name}: 再試行しても処理できませんでした "
        f"(解析失敗 {parse_failures} 回, API エラー {api_failures} 回)"
    ) from last_error


def _request(
    client: anthropic.Anthropic,
    image_path: Path,
    book: CharacterBook,
    model: str,
    final_book: bool,
) -> PageExtraction:
    media_type, data = encode_image(image_path)

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
    extraction.lines = normalize_text(
        cap_context_confidence(
            sort_reading_order(extraction.lines, extraction.panels, spread=is_spread(image_path))
        )
    )
    return extraction
