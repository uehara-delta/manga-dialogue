import os
import threading
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Callable, TypeVar

from pydantic import BaseModel

T = TypeVar("T", bound=BaseModel)


class TransientError(Exception):
    """過負荷・レート制限・接続エラーなど、待って再試行すべき失敗"""


class ParseError(Exception):
    """応答が壊れていて構造化出力を得られなかった。すぐ再試行してよい失敗"""


class Refused(Exception):
    """モデルが処理を拒否した"""


class Cancelled(Exception):
    """中断要求（SIGTERM / SIGINT）を受けた"""


@dataclass(frozen=True)
class Usage:
    input_tokens: int = 0
    output_tokens: int = 0

    def __add__(self, other: "Usage") -> "Usage":
        return Usage(self.input_tokens + other.input_tokens, self.output_tokens + other.output_tokens)


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

# 1 リクエストの上限（秒）。超えたら一時的エラーとして再試行する
REQUEST_TIMEOUT_SECONDS = float(os.environ.get("MANGA_DIALOGUE_REQUEST_TIMEOUT", "600"))
CONNECT_TIMEOUT_SECONDS = 30.0
READ_TIMEOUT_SECONDS = 120.0


class VisionModel(ABC):
    """画像とテキストを受け取り、pydantic スキーマに沿った構造化出力を返すモデル"""

    # 中断要求を確認する関数。CLI がシグナルハンドラと接続する
    cancel_requested: Callable[[], bool] | None = None

    def __init__(self, model: str) -> None:
        self.model = model
        self.last_usage = Usage()
        self.total_usage = Usage()

    def _call_with_deadline(self, fn: Callable[[], T]) -> T:
        """fn を別スレッドで実行し、上限時間の超過は TransientError、中断要求は Cancelled にする。

        超過・中断後もスレッド側の HTTP リクエストは SDK 側のタイムアウトまで残るが、
        デーモンスレッドなのでプロセスの終了は妨げない。
        """
        result: dict[str, object] = {}

        def target() -> None:
            try:
                result["value"] = fn()
            except BaseException as e:  # noqa: BLE001 - 呼び出し元で再送出する
                result["error"] = e

        thread = threading.Thread(target=target, daemon=True)
        thread.start()
        deadline = time.monotonic() + REQUEST_TIMEOUT_SECONDS
        while thread.is_alive():
            thread.join(1.0)
            if self.cancel_requested is not None and self.cancel_requested():
                raise Cancelled()
            if time.monotonic() > deadline:
                raise TransientError(f"{REQUEST_TIMEOUT_SECONDS:.0f} 秒以内に応答がありませんでした")
        if "error" in result:
            raise result["error"]  # type: ignore[misc]
        return result["value"]  # type: ignore[return-value]

    def _record(self, usage: Usage) -> None:
        self.last_usage = usage
        self.total_usage = self.total_usage + usage

    @abstractmethod
    def _complete(self, system: str, parts: list[Part], schema: type[T], max_tokens: int) -> T:
        """1 回だけ呼び出す。失敗は TransientError / ParseError / Refused に変換して送出する"""

    def complete(self, system: str, parts: list[Part], schema: type[T], max_tokens: int = 8000) -> T:
        """リトライ付きで呼び出す。解析失敗は短い間隔で、一時的な API 障害は長い間隔で再試行する"""
        last_error: Exception | None = None
        parse_failures = transient_failures = 0
        while parse_failures < MAX_PARSE_ATTEMPTS and transient_failures < MAX_TRANSIENT_ATTEMPTS:
            try:
                return self._call_with_deadline(lambda: self._complete(system, parts, schema, max_tokens))
            except ParseError as e:
                last_error = e
                parse_failures += 1
                self._sleep(2 * parse_failures)
            except TransientError as e:
                last_error = e
                transient_failures += 1
                self._sleep(TRANSIENT_BACKOFF_SECONDS * transient_failures)
        detail = str(last_error).splitlines()[0][:200] if last_error else ""
        raise RuntimeError(
            f"再試行しても処理できませんでした (解析失敗 {parse_failures} 回, API エラー {transient_failures} 回): {detail}"
        ) from last_error

    def _sleep(self, seconds: float) -> None:
        """待機中も中断要求に応える"""
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if self.cancel_requested is not None and self.cancel_requested():
                raise Cancelled()
            time.sleep(min(1.0, end - time.monotonic()))
