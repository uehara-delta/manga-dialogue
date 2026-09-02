import base64

import openai
from pydantic import ValidationError

from manga_dialogue.extract.llm.base import ImagePart, ParseError, Part, Refused, TextPart, TransientError, Usage, VisionModel

TRANSIENT_ERRORS = (
    openai.RateLimitError,
    openai.InternalServerError,
    openai.APIConnectionError,
    openai.APITimeoutError,
)


class OpenAIModel(VisionModel):
    """OpenAI Responses API。構造化出力は responses.parse（pydantic）を使う。

    API キーは環境変数 OPENAI_API_KEY から読む。
    """

    def __init__(self, model: str) -> None:
        super().__init__(model)
        self.client = openai.OpenAI()

    def _complete(self, system, parts, schema, max_tokens):
        content = [_to_part(p) for p in parts]
        try:
            response = self.client.responses.parse(
                model=self.model,
                input=[
                    {"role": "system", "content": system},
                    {"role": "user", "content": content},
                ],
                text_format=schema,
                max_output_tokens=max_tokens,
            )
        except TRANSIENT_ERRORS as e:
            raise TransientError(str(e)) from e
        except ValidationError as e:
            raise ParseError(str(e)) from e
        if response.usage is not None:
            self._record(Usage(response.usage.input_tokens or 0, response.usage.output_tokens or 0))
        refusal = next(
            (c.refusal for item in response.output or [] if getattr(item, "content", None) for c in item.content if getattr(c, "type", "") == "refusal"),
            None,
        )
        if refusal:
            raise Refused(refusal)
        if response.output_parsed is None:
            raise ParseError(f"構造化出力を取得できませんでした (status={response.status})")
        return response.output_parsed


def _to_part(part: Part) -> dict:
    if isinstance(part, ImagePart):
        data = base64.standard_b64encode(part.data).decode("ascii")
        return {"type": "input_image", "image_url": f"data:{part.media_type};base64,{data}"}
    if isinstance(part, TextPart):
        return {"type": "input_text", "text": part.text}
    raise TypeError(type(part))
