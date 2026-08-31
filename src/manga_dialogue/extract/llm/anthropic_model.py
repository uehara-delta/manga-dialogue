import base64

import anthropic
import httpx2 as httpx
from pydantic import ValidationError

from manga_dialogue.extract.llm.base import ImagePart, ParseError, Part, Refused, TextPart, TransientError, Usage, VisionModel

TRANSIENT_ERRORS = (
    anthropic.RateLimitError,
    anthropic.InternalServerError,
    anthropic.OverloadedError,
    anthropic.APIConnectionError,
    anthropic.APITimeoutError,
    httpx.TransportError,
    TimeoutError,
)
STREAM_THRESHOLD = 16000
TRANSIENT_STATUS_CODES = {408, 429, 500, 502, 503, 504, 529}


class AnthropicModel(VisionModel):
    """Anthropic Messages API。構造化出力は output_format（pydantic）を使う"""

    def __init__(self, model: str) -> None:
        super().__init__(model)
        self.client = anthropic.Anthropic()

    def _complete(self, system, parts, schema, max_tokens):
        content = [_to_block(p) for p in parts]
        messages = [{"role": "user", "content": content}]
        try:
            if max_tokens > STREAM_THRESHOLD:
                with self.client.messages.stream(
                    model=self.model, max_tokens=max_tokens, system=system, messages=messages, output_format=schema
                ) as stream:
                    response = stream.get_final_message()
            else:
                response = self.client.messages.parse(
                    model=self.model, max_tokens=max_tokens, system=system, messages=messages, output_format=schema
                )
        except TRANSIENT_ERRORS as e:
            raise TransientError(str(e)) from e
        except anthropic.APIStatusError as e:
            if e.status_code in TRANSIENT_STATUS_CODES:
                raise TransientError(str(e)) from e
            raise
        except ValidationError as e:
            raise ParseError(str(e)) from e
        if response.usage is not None:
            self._record(Usage(response.usage.input_tokens or 0, response.usage.output_tokens or 0))
        if response.stop_reason == "refusal":
            raise Refused("モデルが処理を拒否しました")
        if response.parsed_output is None:
            raise ParseError(f"構造化出力を取得できませんでした (stop_reason={response.stop_reason})")
        return response.parsed_output


def _to_block(part: Part) -> dict:
    if isinstance(part, ImagePart):
        return {
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": part.media_type,
                "data": base64.standard_b64encode(part.data).decode("ascii"),
            },
        }
    if isinstance(part, TextPart):
        return {"type": "text", "text": part.text}
    raise TypeError(type(part))
