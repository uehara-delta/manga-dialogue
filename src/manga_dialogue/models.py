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


class Rename(BaseModel):
    """台帳のキャラ名（主に仮名）が本名に判明したことを表す"""

    from_name: str = Field(description="台帳に載っている現在の名前")
    to_name: str = Field(description="判明した本名")
    confidence: float = Field(ge=0.0, le=1.0, description="同一人物である確信度")
    reason: str = Field(default="", description="そう判断した根拠（呼びかけ・名乗りなど）")


class PageExtraction(BaseModel):
    """LLM が1ページ分の画像に対して返す構造化出力"""

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

    page: int
    image: str
    lines: list[Line]
    new_characters: list[Character]
    renames: list[Rename] = Field(default_factory=list)
    repassed: bool = False

    def needs_repass(self, min_confidence: float) -> bool:
        return any(l.speaker == "不明" or l.confidence < min_confidence for l in self.lines)
