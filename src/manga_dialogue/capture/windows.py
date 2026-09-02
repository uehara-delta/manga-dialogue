import ctypes
import time
from ctypes import wintypes

from PIL import Image

from manga_dialogue.capture.base import CaptureDriver, WindowRect

user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32
gdi32 = ctypes.windll.gdi32
dwmapi = ctypes.windll.dwmapi

KINDLE_EXE = "kindle.exe"
MIN_WINDOW_SIZE = 300

VK_CODES = {
    "space": 0x20,
    "left": 0x25,
    "right": 0x27,
}
# Microsoft Store 版 Kindle（Amazon Kindle: Reading App）はスペースでページ送りできない。
# 右→左に読む漫画では ← が次ページなので、Mac と同じ既定値 "space" を ← に読み替える。
KEY_ALIASES = {"space": "left"}

PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
DWMWA_CLOAKED = 14
SW_RESTORE = 9
VK_MENU = 0x12
KEYEVENTF_KEYUP = 0x0002
INPUT_KEYBOARD = 1
PW_CLIENTONLY = 0x1
PW_RENDERFULLCONTENT = 0x2
DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4

WNDENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)


class _KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", wintypes.WORD),
        ("wScan", wintypes.WORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
    ]


class _INPUT(ctypes.Structure):
    class _U(ctypes.Union):
        _fields_ = [("ki", _KEYBDINPUT), ("padding", ctypes.c_byte * 32)]

    _anonymous_ = ("u",)
    _fields_ = [("type", wintypes.DWORD), ("u", _U)]


class _BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", wintypes.DWORD),
        ("biWidth", wintypes.LONG),
        ("biHeight", wintypes.LONG),
        ("biPlanes", wintypes.WORD),
        ("biBitCount", wintypes.WORD),
        ("biCompression", wintypes.DWORD),
        ("biSizeImage", wintypes.DWORD),
        ("biXPelsPerMeter", wintypes.LONG),
        ("biYPelsPerMeter", wintypes.LONG),
        ("biClrUsed", wintypes.DWORD),
        ("biClrImportant", wintypes.DWORD),
    ]


def _set_dpi_aware() -> None:
    """ウィンドウ座標とスクリーンショットを物理ピクセルで扱う"""
    try:
        if user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)):
            return
    except (AttributeError, OSError):
        pass
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except (AttributeError, OSError):
        pass


def _process_exe(pid: int) -> str:
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not handle:
        return ""
    try:
        buf = ctypes.create_unicode_buffer(1024)
        size = wintypes.DWORD(len(buf))
        if not kernel32.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(size)):
            return ""
        return buf.value
    finally:
        kernel32.CloseHandle(handle)


def _is_cloaked(hwnd: int) -> bool:
    value = wintypes.DWORD()
    dwmapi.DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, ctypes.byref(value), ctypes.sizeof(value))
    return value.value != 0


def _client_rect(hwnd: int) -> WindowRect:
    """クライアント領域（アプリ自身のタイトルバーを含み、OS の枠を含まない）をスクリーン座標で返す"""
    rect = wintypes.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(rect))
    origin = wintypes.POINT(0, 0)
    user32.ClientToScreen(hwnd, ctypes.byref(origin))
    return WindowRect(origin.x, origin.y, rect.right, rect.bottom)


def _find_kindle_windows() -> list[int]:
    found: list[int] = []

    def visit(hwnd: int, _: int) -> bool:
        if not user32.IsWindowVisible(hwnd) or _is_cloaked(hwnd):
            return True
        pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        exe = _process_exe(pid.value)
        if exe.lower().endswith("\\" + KINDLE_EXE):
            found.append(hwnd)
        return True

    user32.EnumWindows(WNDENUMPROC(visit), 0)
    return found


def _print_window(hwnd: int, width: int, height: int) -> Image.Image | None:
    """PrintWindow でクライアント領域だけを描画させる。重なった他のウィンドウやカーソルは写らない"""
    screen_dc = user32.GetDC(0)
    mem_dc = gdi32.CreateCompatibleDC(screen_dc)
    bitmap = gdi32.CreateCompatibleBitmap(screen_dc, width, height)
    try:
        gdi32.SelectObject(mem_dc, bitmap)
        if not user32.PrintWindow(hwnd, mem_dc, PW_CLIENTONLY | PW_RENDERFULLCONTENT):
            return None
        header = _BITMAPINFOHEADER()
        header.biSize = ctypes.sizeof(header)
        header.biWidth = width
        header.biHeight = -height  # トップダウン
        header.biPlanes = 1
        header.biBitCount = 32
        buf = ctypes.create_string_buffer(width * height * 4)
        if not gdi32.GetDIBits(mem_dc, bitmap, 0, height, buf, ctypes.byref(header), 0):
            return None
        return Image.frombuffer("RGB", (width, height), buf.raw, "raw", "BGRX", 0, 1)
    finally:
        gdi32.DeleteObject(bitmap)
        gdi32.DeleteDC(mem_dc)
        user32.ReleaseDC(0, screen_dc)


def _is_blank(img: Image.Image) -> bool:
    lo, hi = img.convert("L").getextrema()
    return lo == hi


def _send_vk(vk: int) -> None:
    inputs = (_INPUT * 2)()
    for i, flags in enumerate((0, KEYEVENTF_KEYUP)):
        inputs[i].type = INPUT_KEYBOARD
        inputs[i].ki = _KEYBDINPUT(vk, 0, flags, 0, None)
    user32.SendInput(2, inputs, ctypes.sizeof(_INPUT))


class WindowsKindleDriver(CaptureDriver):
    """Microsoft Store 版 Kindle（Amazon Kindle: Reading App）用ドライバ。

    Win32 API（ctypes）でウィンドウ検出・前面化・キー送信を行い、PrintWindow で
    Kindle ウィンドウだけを撮影する。特別な権限は不要。
    """

    def __init__(self) -> None:
        _set_dpi_aware()
        self._hwnd: int | None = None

    def find_window(self) -> WindowRect | None:
        candidates = []
        for hwnd in _find_kindle_windows():
            rect = _client_rect(hwnd)
            if rect.width >= MIN_WINDOW_SIZE and rect.height >= MIN_WINDOW_SIZE:
                candidates.append((hwnd, rect))
        if not candidates:
            return None
        self._hwnd, rect = max(candidates, key=lambda c: c[1].width * c[1].height)
        return rect

    def capture(self, rect: WindowRect) -> Image.Image:
        if self._hwnd is not None:
            img = _print_window(self._hwnd, rect.width, rect.height)
            if img is not None and not _is_blank(img):
                return img
        return super().capture(rect)

    def activate(self) -> None:
        if self._hwnd is None and self.find_window() is None:
            raise RuntimeError("Kindle が起動していません。Kindle で本を開いてください")
        hwnd = self._hwnd
        if user32.IsIconic(hwnd):
            user32.ShowWindow(hwnd, SW_RESTORE)
        user32.SetForegroundWindow(hwnd)
        if user32.GetForegroundWindow() != hwnd:
            # 前面化が拒否されたときの定石: Alt を一度押してから再試行する
            _send_vk(VK_MENU)
            user32.SetForegroundWindow(hwnd)
        # カーソルをウィンドウの外（画面左下）に逃がし、ホバー UI を出さない
        user32.SetCursorPos(0, user32.GetSystemMetrics(1) - 1)
        time.sleep(0.5)

    def send_key(self, key: str) -> None:
        _send_vk(VK_CODES[KEY_ALIASES.get(key, key)])
        time.sleep(0.05)
