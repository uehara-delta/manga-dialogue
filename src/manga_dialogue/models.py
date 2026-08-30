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


class PageExtraction(BaseModel):
    """LLM が1ページ分の画像に対して返す構造化出力"""

    lines: list[Line]
    new_characters: list[Character] = Field(
        default_factory=list,
        description="台帳に存在しない新キャラ。名前が判明したもののみ",
    )


class PageResult(BaseModel):
    """ページ番号を付与して保存する抽出結果"""

    page: int
    image: str
    lines: list[Line]
    new_characters: list[Character]
