import time

import Quartz
from AppKit import NSApplicationActivateIgnoringOtherApps, NSRunningApplication

from manga_dialogue.capture.base import CaptureDriver, WindowRect

KINDLE_BUNDLE_ID = "com.amazon.Kindle"
KINDLE_OWNER_NAME = "Kindle"

KEY_CODES = {
    "space": 49,
    "left": 123,
    "right": 124,
}


class MacKindleDriver(CaptureDriver):
    """Kindle for Mac 用ドライバ。Quartz でウィンドウ検出・キー送信を行う。

    「画面収録」と「アクセシビリティ」の許可が必要。
    """

    def find_window(self) -> WindowRect | None:
        windows = Quartz.CGWindowListCopyWindowInfo(
            Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
            Quartz.kCGNullWindowID,
        )
        candidates = [
            w
            for w in windows
            if w.get("kCGWindowOwnerName") == KINDLE_OWNER_NAME and w.get("kCGWindowLayer", 0) == 0
        ]
        if not candidates:
            return None
        largest = max(candidates, key=lambda w: w["kCGWindowBounds"]["Width"] * w["kCGWindowBounds"]["Height"])
        b = largest["kCGWindowBounds"]
        return WindowRect(int(b["X"]), int(b["Y"]), int(b["Width"]), int(b["Height"]))

    def activate(self) -> None:
        apps = NSRunningApplication.runningApplicationsWithBundleIdentifier_(KINDLE_BUNDLE_ID)
        if not apps:
            raise RuntimeError("Kindle が起動していません")
        apps[0].activateWithOptions_(NSApplicationActivateIgnoringOtherApps)
        time.sleep(0.5)

    def send_key(self, key: str) -> None:
        code = KEY_CODES[key]
        for down in (True, False):
            event = Quartz.CGEventCreateKeyboardEvent(None, code, down)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)
            time.sleep(0.05)
