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


def order_panels(panels: list[Panel]) -> list[Panel]:
    """コマ矩形から日本の漫画の読み順（上の段から、段内は右→左）を再帰的に決める。

    まず水平の切れ目で上下に分割し、分割できなければ垂直の切れ目で右から左に分割する。
    """
    if len(panels) <= 1:
        return list(panels)
    rows = _split(panels, axis="y")
    if len(rows) > 1:
        return [q for row in rows for q in order_panels(row)]
    cols = _split(panels, axis="x")
    if len(cols) > 1:
        return [q for col in reversed(cols) for q in order_panels(col)]
    return sorted(panels, key=lambda q: (q.y0, -q.x1))


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


def sort_reading_order(lines: list["Line"], panels: list[Panel] | None = None) -> list["Line"]:
    """コマを読み順に並べ、同じコマ内は座標から 右→左、上→下 の読み順に並べ替える。

    panels が与えられればその矩形から読み順を決め、panel 番号を 1 から振り直す。
    横位置が COLUMN_BAND 以内の吹き出しは同じ縦の列とみなして上から順にする。
    座標のない行は元の順序を保つ。
    """
    if panels:
        ordered = order_panels(panels)
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


def normalize_text(lines: list["Line"]) -> list["Line"]:
    """吹き出し内の改行を詰めて 1 行にする"""
    return [l.model_copy(update={"text": " ".join(l.text.split())}) for l in lines]


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
    lines: list[Line]
    new_characters: list[Character]
    renames: list[Rename] = Field(default_factory=list)
    repassed: bool = False

    def needs_repass(self, min_confidence: float) -> bool:
        return any(l.speaker == "不明" or l.confidence < min_confidence for l in self.lines)
