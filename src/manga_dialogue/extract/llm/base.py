import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import TypeVar

from pydantic import BaseModel

T = TypeVar("T", bound=BaseModel)


class TransientError(Exception):
    """過負荷・レート制限・接続エラーなど、待って再試行すべき失敗"""


class ParseError(Exception):
    """応答が壊れていて構造化出力を得られなかった。すぐ再試行してよい失敗"""


class Refused(Exception):
    """モデルが処理を拒否した"""


@dataclass(frozen=True)
class ImagePart:
    media_type: str
    data: bytes


@dataclass(frozen=True)
class TextPart:
    text: str


Part = ImagePart | TextPart

MAX_PARSE_ATTEMPTS = 3
MAX_TRANSIENT_ATTEMPTS = 5
TRANSIENT_BACKOFF_SECONDS = 30


class VisionModel(ABC):
    """画像とテキストを受け取り、pydantic スキーマに沿った構造化出力を返すモデル"""

    def __init__(self, model: str) -> None:
        self.model = model

    @abstractmethod
    def _complete(self, system: str, parts: list[Part], schema: type[T], max_tokens: int) -> T:
        """1 回だけ呼び出す。失敗は TransientError / ParseError / Refused に変換して送出する"""

    def complete(self, system: str, parts: list[Part], schema: type[T], max_tokens: int = 8000) -> T:
        """リトライ付きで呼び出す。解析失敗は短い間隔で、一時的な API 障害は長い間隔で再試行する"""
        last_error: Exception | None = None
        parse_failures = transient_failures = 0
        while parse_failures < MAX_PARSE_ATTEMPTS and transient_failures < MAX_TRANSIENT_ATTEMPTS:
            try:
                return self._complete(system, parts, schema, max_tokens)
            except ParseError as e:
                last_error = e
                parse_failures += 1
                time.sleep(2 * parse_failures)
            except TransientError as e:
                last_error = e
                transient_failures += 1
                time.sleep(TRANSIENT_BACKOFF_SECONDS * transient_failures)
        raise RuntimeError(
            f"再試行しても処理できませんでした (解析失敗 {parse_failures} 回, API エラー {transient_failures} 回)"
        ) from last_error
