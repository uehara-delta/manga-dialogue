"""キャプチャ画像から Kindle アプリの枠と余白を切り落とす（OS 非依存の画像処理）。

- 背景色は左下隅の画素から決める（ライト／ダークテーマの両方に対応）
- 上端のタイトルバー: 画面の上部 TITLE_SCAN_RATIO の範囲で、背景でない画素が左右の端
  （EDGE_RATIO ずつ）にしかない行を「アプリの枠」とみなして落とす。ページ本体は中央にあるので、
  中央に背景でない画素が現れた行から下を残す
- 左右: 背景でない画素を含む列の連続した区間（切れ目が GAP_RATIO 未満なら同じ区間）のうち、
  画面の端（EDGE_UI_RATIO 以内）にある幅 UI_MAX_RATIO 未満の細い区間はしおりアイコンなどの
  UI 部品とみなして除き、残りの区間をすべて含む範囲を残す（見開きの片側が空白でも落とさない）
- 上下: 選んだ列の範囲で背景でない画素を含む行の範囲を残す
"""
from PIL import Image, ImageChops

BG_TOLERANCE = 24
TITLE_SCAN_RATIO = 0.08
EDGE_RATIO = 0.2
GAP_RATIO = 0.05
EDGE_UI_RATIO = 0.06
UI_MAX_RATIO = 0.03

Box = tuple[int, int, int, int]


def _foreground_mask(img: Image.Image) -> Image.Image:
    """背景色と十分に異なる画素を 255、それ以外を 0 にした L 画像"""
    rgb = img.convert("RGB")
    w, h = rgb.size
    bg = Image.new("RGB", rgb.size, rgb.getpixel((0, h - 1)))
    r, g, b = ImageChops.difference(rgb, bg).split()
    diff = ImageChops.lighter(ImageChops.lighter(r, g), b)
    return diff.point(lambda v: 255 if v > BG_TOLERANCE else 0)


def _runs(projection: list[int], max_gap: int) -> list[tuple[int, int]]:
    """0/1 の投影から、max_gap 未満の切れ目を無視した 1 の区間 [start, end) を列挙する"""
    runs: list[tuple[int, int]] = []
    start: int | None = None
    last = -1
    for i, v in enumerate(projection):
        if not v:
            continue
        if start is None:
            start = i
        elif i - last > max_gap:
            runs.append((start, last + 1))
            start = i
        last = i
    if start is not None:
        runs.append((start, last + 1))
    return runs


def _is_edge_ui(run: tuple[int, int], width: int) -> bool:
    start, end = run
    narrow = end - start < width * UI_MAX_RATIO
    at_edge = start < width * EDGE_UI_RATIO or end > width * (1 - EDGE_UI_RATIO)
    return narrow and at_edge


def find_content_box(img: Image.Image) -> Box | None:
    """残すべき領域 (left, top, right, bottom) を返す。ページ本体が見つからなければ None"""
    mask = _foreground_mask(img)
    w, h = mask.size
    scan = int(h * TITLE_SCAN_RATIO)
    center = mask.crop((int(w * EDGE_RATIO), 0, int(w * (1 - EDGE_RATIO)), scan)).getbbox()
    top = scan if center is None else center[1]
    body = mask.crop((0, top, w, h))
    cols, _ = body.getprojection()
    runs = [r for r in _runs(list(cols), int(w * GAP_RATIO)) if not _is_edge_ui(r, w)]
    if not runs:
        return None
    left, right = runs[0][0], runs[-1][1]
    rows = body.crop((left, 0, right, body.height)).getbbox()
    if rows is None:
        return None
    return (left, top + rows[1], right, top + rows[3])


def trim(img: Image.Image) -> tuple[Image.Image, Box]:
    """切り落とした画像と、元画像上での残した領域を返す"""
    box = find_content_box(img)
    if box is None:
        return img, (0, 0, img.width, img.height)
    return img.crop(box), box


def remap(value: float, lo: int, hi: int, size: int) -> float:
    """元画像に対する割合 value を、元画像の [lo, hi) を切り出した画像に対する割合に変換する"""
    if hi <= lo:
        return value
    return round(min(1.0, max(0.0, (value * size - lo) / (hi - lo))), 4)
