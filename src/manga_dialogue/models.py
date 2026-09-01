import re
from typing import Literal

from pydantic import BaseModel, Field


class Character(BaseModel):
    """キャラ台帳の1エントリ"""

    name: str
    aliases: list[str] = Field(default_factory=list)
    appearance: str = ""


class Line(BaseModel):
    """1つの吹き出し・ナレーションに対応するセリフ"""

    panel: int = Field(description="ページ内のコマ番号（右→左、上→下の順で1始まり）")
    speaker: str = Field(description="話者名。ナレーションは「ナレーション」、不明は「不明」")
    text: str
    confidence: float = Field(ge=0.0, le=1.0, description="話者特定の確信度")
    basis: Literal["tail", "context", "unknown"] | None = Field(
        default=None,
        description="話者を決めた根拠。tail=吹き出しの尻尾が指す人物、context=尻尾では決まらず文脈から推定、unknown=不明",
    )
    x: float | None = Field(default=None, ge=0.0, le=1.0, description="吹き出し中心の横位置。画像左端 0.0〜右端 1.0")
    y: float | None = Field(default=None, ge=0.0, le=1.0, description="吹き出し中心の縦位置。画像上端 0.0〜下端 1.0")
    manual: bool = Field(default=False, description="人手または fix で修正済み。再抽出で上書きしない")


class Rename(BaseModel):
    """台帳のキャラ名（主に仮名）が本名に判明したことを表す"""

    from_name: str = Field(description="台帳に載っている現在の名前")
    to_name: str = Field(description="判明した本名")
    confidence: float = Field(ge=0.0, le=1.0, description="同一人物である確信度")
    reason: str = Field(default="", description="そう判断した根拠（呼びかけ・名乗りなど）")


class Panel(BaseModel):
    """ページ内のコマの矩形（画像に対する相対座標）"""

    id: int = Field(description="このページ内でコマを識別する番号（順序は問わない）")
    x0: float = Field(ge=0.0, le=1.0, description="左端")
    y0: float = Field(ge=0.0, le=1.0, description="上端")
    x1: float = Field(ge=0.0, le=1.0, description="右端")
    y1: float = Field(ge=0.0, le=1.0, description="下端")


GAP = 0.01


SPREAD_CENTER = 0.5
SPAN_MARGIN = 0.1


def order_panels(panels: list[Panel], spread: bool = False) -> list[Panel]:
    """コマ矩形から日本の漫画の読み順を決める。

    単ページ: 水平の切れ目で上下に分割し、分割できなければ垂直の切れ目で右から左に分割する
    （再帰）。
    見開き: 右ページと左ページはそれぞれ独立に読む（右ページの最後のコマが左ページの最初の
    コマより前）。ただし両ページにまたがるコマがある場合は、そのコマを境に上下を分け、
    「上の部分（右→左ページ）→ またがるコマ → 下の部分（右→左ページ）」の順にする。
    """
    if len(panels) <= 1:
        return list(panels)
    if spread:
        return _order_spread(panels)
    rows = _split(panels, axis="y")
    if len(rows) > 1:
        return [q for row in rows for q in order_panels(row)]
    cols = _split(panels, axis="x")
    if len(cols) > 1:
        return [q for col in reversed(cols) for q in order_panels(col)]
    return sorted(panels, key=lambda q: (q.y0, -q.x1))


def _is_spanning(q: Panel) -> bool:
    """両ページに SPAN_MARGIN 以上食い込むコマだけを「またがるコマ」とみなす。

    矩形の見積もり誤差で中央線をわずかに越えただけのコマは、中心のあるページに属する。
    """
    return q.x0 < SPREAD_CENTER - SPAN_MARGIN and q.x1 > SPREAD_CENTER + SPAN_MARGIN


def _order_spread(panels: list[Panel]) -> list[Panel]:
    spanning = sorted((q for q in panels if _is_spanning(q)), key=lambda q: q.y0)
    right = [q for q in panels if not _is_spanning(q) and (q.x0 + q.x1) / 2 >= SPREAD_CENTER]
    left = [q for q in panels if not _is_spanning(q) and (q.x0 + q.x1) / 2 < SPREAD_CENTER]
    if not spanning:
        return order_panels(right) + order_panels(left)
    top_span = spanning[0]
    above = [q for q in panels if q is not top_span and q.y1 <= top_span.y0 + GAP]
    below = [q for q in panels if q is not top_span and q not in above]
    return _order_spread(above) + [top_span] + _order_spread(below)


def _split(panels: list[Panel], axis: str) -> list[list[Panel]]:
    lo, hi = ("y0", "y1") if axis == "y" else ("x0", "x1")
    items = sorted(panels, key=lambda q: getattr(q, lo))
    groups: list[list[Panel]] = [[items[0]]]
    end = getattr(items[0], hi)
    for q in items[1:]:
        if getattr(q, lo) >= end - GAP:
            groups.append([q])
        else:
            groups[-1].append(q)
        end = max(end, getattr(q, hi))
    return groups


COLUMN_BAND = 0.15


CONTEXT_CONFIDENCE_CAP = 0.6


def cap_context_confidence(lines: list["Line"]) -> list["Line"]:
    """尻尾ではなく文脈から推定した話者の confidence を上限で抑える"""
    return [
        l.model_copy(update={"confidence": min(l.confidence, CONTEXT_CONFIDENCE_CAP)})
        if l.basis == "context" else l
        for l in lines
    ]


MIRROR_TOLERANCE = 0.03


def unmirror_x(lines: list["Line"], panels: list[Panel]) -> list["Line"]:
    """右端から測った x（1 − x）で返された吹き出しを補正する。

    モデルが右→左の読み順と混同して x を鏡像で返すことがある。吹き出しの x が属するコマの
    矩形の外にあり、1 − x なら中に収まる場合に限って反転する。
    """
    by_id = {q.id: q for q in panels}
    fixed: list[Line] = []
    for l in lines:
        q = by_id.get(l.panel)
        if q is None or l.x is None:
            fixed.append(l)
            continue
        lo, hi = q.x0 - MIRROR_TOLERANCE, q.x1 + MIRROR_TOLERANCE
        mirrored = 1.0 - l.x
        if not (lo <= l.x <= hi) and (lo <= mirrored <= hi):
            fixed.append(l.model_copy(update={"x": round(mirrored, 4)}))
        else:
            fixed.append(l)
    return fixed


def arrange(
    lines: list["Line"], panels: list[Panel], spread: bool = False
) -> tuple[list["Line"], list[Panel]]:
    """座標の補正と読み順の決定をまとめて行い、読み順に振り直したコマ矩形も返す"""
    lines = unmirror_x(lines, panels)
    ordered = order_panels(panels, spread=spread)
    renumbered = [q.model_copy(update={"id": i + 1}) for i, q in enumerate(ordered)]
    return sort_reading_order(lines, panels, spread=spread), renumbered


def sort_reading_order(
    lines: list["Line"], panels: list[Panel] | None = None, spread: bool = False
) -> list["Line"]:
    """コマを読み順に並べ、同じコマ内は座標から 右→左、上→下 の読み順に並べ替える。

    panels が与えられればその矩形から読み順を決め、panel 番号を 1 から振り直す。
    spread=True なら見開きとして扱う（order_panels 参照）。
    横位置が COLUMN_BAND 以内の吹き出しは同じ縦の列とみなして上から順にする。
    座標のない行は元の順序を保つ。
    """
    if panels:
        ordered = order_panels(panels, spread=spread)
        renumber = {q.id: i + 1 for i, q in enumerate(ordered)}
        lines = [l.model_copy(update={"panel": renumber.get(l.panel, l.panel)}) for l in lines]
    result: list[Line] = []
    panel_ids = sorted({l.panel for l in lines})
    for panel in panel_ids:
        group = [l for l in lines if l.panel == panel]
        if any(l.x is None or l.y is None for l in group):
            result.extend(group)
            continue
        remaining = sorted(group, key=lambda l: -l.x)
        while remaining:
            anchor = remaining[0]
            column = [l for l in remaining if _same_column(anchor, l)]
            column.sort(key=lambda l: l.y)
            result.extend(column)
            remaining = [l for l in remaining if l not in column]
    return result


def _same_column(anchor: "Line", other: "Line") -> bool:
    """anchor（より右にある吹き出し）と other が縦に積まれた関係かどうか。

    横のずれが小さく、かつ横のずれより縦のずれが大きければ同じ列とみなす。
    横に並んだ吹き出し（縦のずれが小さい）は別の列として右が先になる。
    """
    if other is anchor:
        return True
    dx = anchor.x - other.x
    dy = abs(other.y - anchor.y)
    return dx <= COLUMN_BAND and dy >= dx


_ASCII_GAP = re.compile(r"(?<=[A-Za-z0-9])\s+|\s+(?=[A-Za-z0-9])")
_OTHER_GAP = re.compile(r"\s+")


def collapse_whitespace(text: str) -> str:
    """吹き出し内の改行・空白を詰める。英数字に隣接する空白だけは半角スペース 1 つを残す"""
    text = _ASCII_GAP.sub("\x00", text.strip())
    text = _OTHER_GAP.sub("", text)
    return text.replace("\x00", " ")


def normalize_text(lines: list["Line"]) -> list["Line"]:
    """吹き出し内の改行を詰めて 1 行にする"""
    return [l.model_copy(update={"text": collapse_whitespace(l.text)}) for l in lines]


class PageExtraction(BaseModel):
    """LLM が1ページ分の画像に対して返す構造化出力"""

    panels: list[Panel] = Field(default_factory=list, description="ページ内の全コマの矩形")
    lines: list[Line]
    new_characters: list[Character] = Field(
        default_factory=list,
        description="台帳に存在しない新キャラ。名前不明でも継続登場しそうなら仮名で登録",
    )
    renames: list[Rename] = Field(
        default_factory=list,
        description="台帳の既存キャラ（主に仮名）の本名が判明した場合の改名指示",
    )


class PageResult(BaseModel):
    """ページ番号を付与して保存する抽出結果"""

    volume: int = 1
    page: int
    image: str
    panels: list[Panel] = Field(default_factory=list, description="読み順に番号を振ったコマの矩形")
    lines: list[Line]
    new_characters: list[Character]
    renames: list[Rename] = Field(default_factory=list)
    repassed: bool = False
    manual: bool = Field(default=False, description="ページ全体を人手で確定済み。再抽出で上書きしない")

    def needs_repass(self, min_confidence: float) -> bool:
        return any(l.speaker == "不明" or l.confidence < min_confidence for l in self.lines)

    def is_locked(self) -> bool:
        return self.manual or any(l.manual for l in self.lines)
