from manga_dialogue.capture.base import CaptureDriver, WindowRect


class WindowsKindleDriver(CaptureDriver):
    """Kindle for PC 用ドライバ（未実装）"""

    def find_window(self) -> WindowRect | None:
        raise NotImplementedError

    def activate(self) -> None:
        raise NotImplementedError

    def send_key(self, key: str) -> None:
        raise NotImplementedError
