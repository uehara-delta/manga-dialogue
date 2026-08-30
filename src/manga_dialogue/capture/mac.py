import time

import Quartz
from AppKit import NSApplicationActivateIgnoringOtherApps, NSRunningApplication
from PIL import Image

from manga_dialogue.capture.base import CaptureDriver, WindowRect

KINDLE_BUNDLE_ID = "com.amazon.Lassen"
KINDLE_OWNER_NAME = "Kindle"

MIN_WINDOW_SIZE = 300

KEY_CODES = {
    "space": 49,
    "left": 123,
    "right": 124,
}


class MacKindleDriver(CaptureDriver):
    """Kindle for Mac 用ドライバ。Quartz でウィンドウ検出・キー送信を行う。

    「画面収録」と「アクセシビリティ」の許可が必要。
    """

    def __init__(self) -> None:
        self._window_id: int | None = None

    def find_window(self) -> WindowRect | None:
        windows = Quartz.CGWindowListCopyWindowInfo(
            Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
            Quartz.kCGNullWindowID,
        )
        candidates = [
            w
            for w in windows
            if w.get("kCGWindowOwnerName") == KINDLE_OWNER_NAME
            and w.get("kCGWindowLayer", 0) == 0
            and w["kCGWindowBounds"]["Width"] >= MIN_WINDOW_SIZE
            and w["kCGWindowBounds"]["Height"] >= MIN_WINDOW_SIZE
        ]
        if not candidates:
            return None
        largest = max(candidates, key=lambda w: w["kCGWindowBounds"]["Width"] * w["kCGWindowBounds"]["Height"])
        b = largest["kCGWindowBounds"]
        self._window_id = int(largest["kCGWindowNumber"])
        return WindowRect(int(b["X"]), int(b["Y"]), int(b["Width"]), int(b["Height"]))

    def capture(self, rect: WindowRect) -> Image.Image:
        """Kindle ウィンドウだけを物理解像度（Retina なら 2 倍）で撮影する。

        ウィンドウ単位のキャプチャなので、カーソルや重なった他のウィンドウは写らない。
        """
        if self._window_id is None:
            return super().capture(rect)
        cg = Quartz.CGWindowListCreateImage(
            Quartz.CGRectNull,
            Quartz.kCGWindowListOptionIncludingWindow,
            self._window_id,
            Quartz.kCGWindowImageBoundsIgnoreFraming | Quartz.kCGWindowImageBestResolution,
        )
        if cg is None:
            return super().capture(rect)
        width = Quartz.CGImageGetWidth(cg)
        height = Quartz.CGImageGetHeight(cg)
        stride = Quartz.CGImageGetBytesPerRow(cg)
        data = Quartz.CGDataProviderCopyData(Quartz.CGImageGetDataProvider(cg))
        img = Image.frombuffer("RGBA", (width, height), bytes(data), "raw", "BGRA", stride, 1)
        return img.convert("RGB")

    def activate(self) -> None:
        apps = NSRunningApplication.runningApplicationsWithBundleIdentifier_(KINDLE_BUNDLE_ID)
        if not apps:
            raise RuntimeError("Kindle が起動していません")
        apps[0].activateWithOptions_(NSApplicationActivateIgnoringOtherApps)
        Quartz.CGWarpMouseCursorPosition((0, 0))
        time.sleep(0.5)

    def send_key(self, key: str) -> None:
        code = KEY_CODES[key]
        for down in (True, False):
            event = Quartz.CGEventCreateKeyboardEvent(None, code, down)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)
            time.sleep(0.05)
