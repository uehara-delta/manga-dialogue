import io
from pathlib import Path

from PIL import Image

from manga_dialogue.extract.characters import CharacterBook
from manga_dialogue.extract.llm import ImagePart, TextPart, VisionModel
from manga_dialogue.extract.prompt import SYSTEM_PROMPT, build_user_prompt
from manga_dialogue.models import PageExtraction, cap_context_confidence, normalize_text, sort_reading_order

DEFAULT_MODEL = "gemini-3.7-flash"
MAX_LONG_EDGE = 2576
MAX_IMAGE_BYTES = 4_500_000
SPREAD_ASPECT = 1.15
EXTRACT_MAX_TOKENS = 32000


class ExtractionFailed(RuntimeError):
    """リトライしても有効な構造化出力が得られなかった"""


def is_spread(image_path: Path) -> bool:
    """横長の画像（縦横比が SPREAD_ASPECT 超）を見開きとみなす"""
    with Image.open(image_path) as img:
        w, h = img.size
    return w / h > SPREAD_ASPECT


def load_image_part(image_path: Path) -> ImagePart:
    """API に送る画像を用意する。

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
    return ImagePart(media_type, buf.getvalue())


def extract_page(
    llm: VisionModel,
    image_path: Path,
    book: CharacterBook,
    final_book: bool = False,
) -> PageExtraction:
    """画像1枚をモデルに送り、セリフと新キャラを構造化して返す

    final_book=True のときは処理済み範囲を反映した台帳であることをプロンプトで伝える。
    """
    parts = [load_image_part(image_path), TextPart(build_user_prompt(book.to_prompt_text(), final_book=final_book))]
    try:
        extraction = llm.complete(SYSTEM_PROMPT, parts, PageExtraction, max_tokens=EXTRACT_MAX_TOKENS)
    except RuntimeError as e:
        raise ExtractionFailed(f"{image_path.name}: {e}") from e
    extraction.lines = normalize_text(
        cap_context_confidence(
            sort_reading_order(extraction.lines, extraction.panels, spread=is_spread(image_path))
        )
    )
    return extraction
