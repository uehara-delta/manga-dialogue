import base64
from pathlib import Path

import anthropic

from manga_dialogue.extract.characters import CharacterBook
from manga_dialogue.extract.prompt import SYSTEM_PROMPT, build_user_prompt
from manga_dialogue.models import PageExtraction

DEFAULT_MODEL = "claude-opus-5"

MEDIA_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp"}


class ExtractionRefused(RuntimeError):
    pass


def extract_page(
    client: anthropic.Anthropic,
    image_path: Path,
    book: CharacterBook,
    model: str = DEFAULT_MODEL,
    final_book: bool = False,
) -> PageExtraction:
    """画像1枚を Anthropic API に送り、セリフと新キャラを構造化して返す

    final_book=True のときは台帳が完成済みであることをプロンプトで伝え、
    「不明」を減らすよう促す。
    """
    data = base64.standard_b64encode(image_path.read_bytes()).decode("ascii")
    media_type = MEDIA_TYPES[image_path.suffix.lower()]

    response = client.messages.parse(
        model=model,
        max_tokens=16000,
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
        raise RuntimeError(f"{image_path.name}: 構造化出力を取得できませんでした (stop_reason={response.stop_reason})")
    return response.parsed_output
