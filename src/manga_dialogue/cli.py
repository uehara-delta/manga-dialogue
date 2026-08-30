import json
from pathlib import Path

import anthropic
import typer

from manga_dialogue.extract.characters import CharacterBook
from manga_dialogue.extract.extractor import DEFAULT_MODEL, extract_page
from manga_dialogue.extract.renames import apply_rename, record_pending
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


def _process_page(
    client: anthropic.Anthropic,
    work: Work,
    image: Path,
    book: CharacterBook,
    model: str,
    rename_threshold: float,
    final_book: bool = False,
) -> PageResult:
    """1ページを抽出し、台帳と出力 JSON を更新する。

    LLM が返した改名指示は confidence が閾値以上なら台帳と過去の出力に適用し、
    未満なら pending_renames.jsonl に記録するだけにする。
    """
    page = int(image.stem)
    typer.echo(f"page {page:04d} ... ", nl=False)
    extraction = extract_page(client, image, book, model=model, final_book=final_book)
    added = book.merge(extraction.new_characters)
    book.save()
    result = PageResult(
        page=page,
        image=image.name,
        lines=extraction.lines,
        new_characters=extraction.new_characters,
        renames=extraction.renames,
        repassed=final_book,
    )
    work.output_path(page).write_text(
        json.dumps(result.model_dump(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    notes = [f"{len(extraction.lines)} lines"]
    if added:
        notes.append(f"新キャラ: {', '.join(c.name for c in added)}")
    for r in extraction.renames:
        if book.find(r.from_name) is None:
            continue
        if r.confidence >= rename_threshold:
            n = apply_rename(work, book, r.from_name, r.to_name)
            notes.append(f"改名: {r.from_name} → {r.to_name} ({n} 件置換)")
        else:
            record_pending(work, page, r)
            notes.append(f"改名候補(保留): {r.from_name} → {r.to_name} ({r.confidence:.2f})")
    typer.echo(", ".join(notes))
    return result


@app.command()
def extract(
    title: str = typer.Argument(help="作品名（works/<title>/captures を処理）"),
    model: str = typer.Option(DEFAULT_MODEL, help="使用するモデル ID"),
    resume: bool = typer.Option(False, help="出力済みページをスキップして再開"),
    rename_threshold: float = typer.Option(0.8, help="この confidence 以上の改名指示を自動適用"),
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
        if resume and work.output_path(int(image.stem)).exists():
            continue
        _process_page(client, work, image, book, model, rename_threshold)

    typer.echo(f"完了: {work.output_dir} / 台帳 {len(book.characters)} 名")


@app.command()
def repass(
    title: str = typer.Argument(help="作品名"),
    model: str = typer.Option(DEFAULT_MODEL, help="使用するモデル ID"),
    min_confidence: float = typer.Option(0.7, help="この値未満の confidence を含むページを再抽出"),
    all_pages: bool = typer.Option(False, "--all", help="条件に関係なく全ページを再抽出"),
    dry_run: bool = typer.Option(False, help="対象ページの一覧だけ表示して終了"),
    rename_threshold: float = typer.Option(0.8, help="この confidence 以上の改名指示を自動適用"),
    root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ"),
) -> None:
    """処理済み範囲の台帳を使い、「不明」や低 confidence を含むページだけ再抽出する

    extract を最後まで通した後に実行する。対象ページの出力 JSON は上書きされる。
    """
    work = Work(title, root)
    book = CharacterBook.load(work.characters_path)
    if not book.characters:
        typer.echo(f"台帳が空です。先に extract を実行してください: {work.characters_path}", err=True)
        raise typer.Exit(1)

    targets: list[Path] = []
    for image in work.capture_images():
        out = work.output_path(int(image.stem))
        if not out.exists():
            continue
        result = PageResult.model_validate_json(out.read_text(encoding="utf-8"))
        if all_pages or result.needs_repass(min_confidence):
            targets.append(image)

    typer.echo(f"再抽出対象: {len(targets)} ページ（台帳 {len(book.characters)} 名）")
    if dry_run or not targets:
        for t in targets:
            typer.echo(f"  {t.name}")
        return

    client = anthropic.Anthropic()
    for image in targets:
        _process_page(client, work, image, book, model, rename_threshold, final_book=True)

    typer.echo(f"完了: {len(targets)} ページ再抽出")


@app.command()
def rename(
    title: str = typer.Argument(help="作品名"),
    from_name: str = typer.Argument(help="台帳にある現在の名前（仮名など）"),
    to_name: str = typer.Argument(help="新しい名前"),
    root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ"),
) -> None:
    """台帳のキャラを手動で改名し、出力済み JSON の speaker も置き換える"""
    work = Work(title, root)
    book = CharacterBook.load(work.characters_path)
    if book.find(from_name) is None:
        typer.echo(f"台帳に見つかりません: {from_name}", err=True)
        raise typer.Exit(1)
    n = apply_rename(work, book, from_name, to_name)
    typer.echo(f"改名: {from_name} → {to_name} / 出力 {n} 件置換 / 台帳 {len(book.characters)} 名")


if __name__ == "__main__":
    app()
