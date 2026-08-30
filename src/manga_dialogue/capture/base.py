import sys
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Callable

import mss
from PIL import Image, ImageChops

from manga_dialogue.workspace import Work


@dataclass(frozen=True)
class WindowRect:
    """スクリーン座標系でのウィンドウ矩形（論理ピクセル）"""

    left: int
    top: int
    width: int
    height: int


class CaptureDriver(ABC):
    """Kindle アプリのキャプチャ操作を OS ごとに実装する抽象クラス。

    OS 依存の処理は find_window / activate / send_key の3つに閉じ込め、
    キャプチャと最終ページ判定を含むループ処理は run() で共通化する。
    """

    @abstractmethod
    def find_window(self) -> WindowRect | None:
        """Kindle のウィンドウ矩形を返す。見つからなければ None"""

    @abstractmethod
    def activate(self) -> None:
        """Kindle を前面化する"""

    @abstractmethod
    def send_key(self, key: str) -> None:
        """前面のアプリにキー入力を送る。key は "space" / "left" / "right"""

    def capture(self, rect: WindowRect) -> Image.Image:
        with mss.mss() as sct:
            shot = sct.grab(
                {"left": rect.left, "top": rect.top, "width": rect.width, "height": rect.height}
            )
        return Image.frombytes("RGB", shot.size, shot.bgra, "raw", "BGRX")

    def run(
        self,
        work: Work,
        max_pages: int,
        delay: float,
        key: str,
        start: int = 1,
        on_page: Callable[[int], None] | None = None,
    ) -> int:
        """ページ送りしながら保存し、保存したページ数を返す。

        ページ送り後に画像が変化しなかった時点で最終ページとみなして終了する。
        """
        work.ensure_dirs()
        self.activate()
        time.sleep(delay)
        rect = self.find_window()
        if rect is None:
            raise RuntimeError("Kindle のウィンドウが見つかりません。Kindle で本を開いてください")

        prev: Image.Image | None = None
        saved = 0
        for i in range(max_pages):
            page = start + i
            img = self.capture(rect)
            if prev is not None and _same_image(prev, img):
                break
            img.save(work.capture_path(page))
            saved += 1
            if on_page:
                on_page(page)
            prev = img
            self.send_key(key)
            time.sleep(delay)
        return saved


def _same_image(a: Image.Image, b: Image.Image) -> bool:
    if a.size != b.size:
        return False
    return ImageChops.difference(a, b).getbbox() is None


def get_driver() -> CaptureDriver:
    if sys.platform == "darwin":
        from manga_dialogue.capture.mac import MacKindleDriver

        return MacKindleDriver()
    if sys.platform == "win32":
        from manga_dialogue.capture.windows import WindowsKindleDriver

        return WindowsKindleDriver()
    raise RuntimeError(f"未対応のプラットフォームです: {sys.platform}")
