from typing import Any

from google import genai
from google.genai import errors, types
from pydantic import ValidationError

from manga_dialogue.extract.llm.base import ImagePart, ParseError, Part, TextPart, TransientError, Usage, VisionModel

RETRYABLE_CLIENT_CODES = {429, 408}


class GeminiModel(VisionModel):
    """Google Gemini API（google-genai SDK）。構造化出力は response_json_schema を使う。

    API キーは環境変数 GEMINI_API_KEY（または GOOGLE_API_KEY）から読む。
    """

    def __init__(self, model: str) -> None:
        super().__init__(model)
        self.client = genai.Client()

    def _complete(self, system, parts, schema, max_tokens):
        contents = [_to_part(p) for p in parts]
        config = types.GenerateContentConfig(
            system_instruction=system,
            response_mime_type="application/json",
            response_json_schema=simplify_schema(schema.model_json_schema()),
            max_output_tokens=max_tokens,
            media_resolution=types.MediaResolution.MEDIA_RESOLUTION_HIGH,
        )
        try:
            response = self.client.models.generate_content(model=self.model, contents=contents, config=config)
        except errors.ServerError as e:
            raise TransientError(str(e)) from e
        except errors.ClientError as e:
            if e.code in RETRYABLE_CLIENT_CODES:
                raise TransientError(str(e)) from e
            raise
        meta = response.usage_metadata
        if meta is not None:
            self._record(Usage(meta.prompt_token_count or 0, (meta.candidates_token_count or 0) + (meta.thoughts_token_count or 0)))
        text = response.text
        if not text:
            raise ParseError(f"応答が空でした (prompt_feedback={response.prompt_feedback})")
        try:
            return schema.model_validate_json(text)
        except ValidationError as e:
            raise ParseError(str(e)) from e


def _to_part(part: Part) -> Any:
    if isinstance(part, ImagePart):
        return types.Part.from_bytes(data=part.data, mime_type=part.media_type)
    if isinstance(part, TextPart):
        return part.text
    raise TypeError(type(part))


def simplify_schema(schema: dict) -> dict:
    """pydantic の JSON Schema を Gemini が受け付ける形に整える。

    $ref / $defs を展開し、title と default を落とす。
    """
    defs = schema.get("$defs", {})

    def resolve(node: Any) -> Any:
        if isinstance(node, dict):
            if "$ref" in node:
                name = node["$ref"].split("/")[-1]
                return resolve(defs[name])
            return {k: resolve(v) for k, v in node.items() if k not in ("title", "default", "$defs")}
        if isinstance(node, list):
            return [resolve(v) for v in node]
        return node

    return resolve(schema)
