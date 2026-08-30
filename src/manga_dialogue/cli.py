import json
from pathlib import Path

import anthropic
import typer

from manga_dialogue.extract.characters import CharacterBook
from manga_dialogue.extract.extractor import DEFAULT_MODEL, extract_page
from manga_dialogue.models import PageResult
from manga_dialogue.workspace import DEFAULT_ROOT, Work

app = typer.Typer(help="Kindle の漫画画面をキャプチャし、セリフを文字起こしする")


@app.command()
def capture(
    title: str = typer.Argument(help="作品名（works/<title>/ に保存）"),
    max_pages: int = typer.Option(300, help="最大キャプチャページ数"),
    delay: float = typer.Option(1.0, help="ページ送り後の待機秒数"),
    key: str = typer.Option("space", help="ページ送りキー: space / left / right"),
    start: int = typer.Option(1, help="開始ページ番号（ファイル名に使用）"),
    root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ"),
) -> None:
    """Kindle を前面化し、ページ送りしながらスクリーンショットを保存する"""
    from manga_dialogue.capture.base import get_driver

    work = Work(title, root)
    driver = get_driver()
    typer.echo(f"キャプチャ開始: {work.captures_dir}")
    saved = driver.run(
        work,
        max_pages=max_pages,
        delay=delay,
        key=key,
        start=start,
        on_page=lambda p: typer.echo(f"  page {p:04d}"),
    )
    typer.echo(f"完了: {saved} ページ保存")


@app.command()
def extract(
    title: str = typer.Argument(help="作品名（works/<title>/captures を処理）"),
    model: str = typer.Option(DEFAULT_MODEL, help="使用するモデル ID"),
    resume: bool = typer.Option(False, help="出力済みページをスキップして再開"),
    root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ"),
) -> None:
    """キャプチャ画像を順に LLM へ送り、ページごとに JSON を出力する"""
    work = Work(title, root)
    images = work.capture_images()
    if not images:
        typer.echo(f"画像がありません: {work.captures_dir}", err=True)
        raise typer.Exit(1)

    work.ensure_dirs()
    book = CharacterBook.load(work.characters_path)
    client = anthropic.Anthropic()

    for image in images:
        page = int(image.stem)
        out = work.output_path(page)
        if resume and out.exists():
            continue
        typer.echo(f"page {page:04d} ... ", nl=False)
        extraction = extract_page(client, image, book, model=model)
        added = book.merge(extraction.new_characters)
        book.save()
        result = PageResult(
            page=page,
            image=image.name,
            lines=extraction.lines,
            new_characters=extraction.new_characters,
        )
        out.write_text(json.dumps(result.model_dump(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        msg = f"{len(extraction.lines)} lines"
        if added:
            msg += f", 新キャラ: {', '.join(c.name for c in added)}"
        typer.echo(msg)

    typer.echo(f"完了: {work.output_dir} / 台帳 {len(book.characters)} 名")


if __name__ == "__main__":
    app()
