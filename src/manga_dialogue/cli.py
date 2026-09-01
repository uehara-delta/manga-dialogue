import json
import os
import signal
import sys
from importlib.metadata import version as pkg_version
from pathlib import Path

import typer

# Windows のコンソール既定（cp932 / cp1252）では日本語や JSON を出力できないため、常に UTF-8 にする
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8", errors="replace")

from manga_dialogue.extract.characters import CharacterBook
from manga_dialogue.extract.consolidate import propose_consolidation
from manga_dialogue.extract.extractor import DEFAULT_MODEL, ExtractionFailed, extract_page
from manga_dialogue.extract.llm import VisionModel, get_model
from manga_dialogue.extract.llm import PROVIDER_PREFIXES
from manga_dialogue.extract.fix import FixPlan, apply_changes, load_pages, propose_fix
from manga_dialogue.extract.pending import PendingRename, PendingStore
from manga_dialogue.extract.renames import apply_rename, record_pending
from manga_dialogue.models import PageResult
from manga_dialogue.output.export import FORMATS, export
from manga_dialogue.workspace import DEFAULT_ROOT, DEFAULT_RUN, RunLocked, Work

app = typer.Typer(help="Kindle の漫画画面をキャプチャし、セリフを文字起こしする")
pending_app = typer.Typer(help="保留中の改名候補を一覧・承認・却下する")
app.add_typer(pending_app, name="pending")


class Reporter:
    """人間向けの表示と、GUI 向けの JSON Lines 出力を切り替える"""

    def __init__(self, as_json: bool) -> None:
        self.as_json = as_json

    def event(self, event: str, _text: str = "", **data) -> None:
        if self.as_json:
            sys.stdout.write(json.dumps({"event": event, **data}, ensure_ascii=False) + "\n")
            sys.stdout.flush()
        elif _text:
            typer.echo(_text)

    def error(self, message: str, **data) -> None:
        if self.as_json:
            sys.stdout.write(json.dumps({"event": "error", "message": message, **data}, ensure_ascii=False) + "\n")
            sys.stdout.flush()
        else:
            typer.echo(message, err=True)


reporter = Reporter(False)


class Cancelled(Exception):
    """SIGTERM / SIGINT による中断要求"""


_cancel_requested = False


def _request_cancel(signum, frame) -> None:
    global _cancel_requested
    _cancel_requested = True


def _install_cancel_handlers() -> None:
    signal.signal(signal.SIGTERM, _request_cancel)
    signal.signal(signal.SIGINT, _request_cancel)


def _check_cancel() -> None:
    if _cancel_requested:
        raise Cancelled()


def _cancelled_exit(**data) -> None:
    reporter.event("cancelled", "中断しました（--resume で続きから処理できます）", **data)
    raise typer.Exit(130)


def _locked_exit(e: RunLocked) -> None:
    reporter.error(str(e), error_type="RunLocked")
    raise typer.Exit(3)


@app.callback()
def main(json_output: bool = typer.Option(False, "--json", help="進捗と結果を JSON Lines で出力する")) -> None:
    global reporter
    reporter = Reporter(json_output)


@app.command()
def info(root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ")) -> None:
    """エンジンの情報を JSON で返す（GUI の疎通確認用）"""
    try:
        ver = pkg_version("manga-dialogue")
    except Exception:
        ver = "unknown"
    data = {
        "version": ver,
        "python": sys.version.split()[0],
        "platform": sys.platform,
        "default_model": DEFAULT_MODEL,
        "providers": {
            "anthropic": {"prefix": "claude-", "api_key": bool(os.environ.get("ANTHROPIC_API_KEY"))},
            "gemini": {"prefix": "gemini-", "api_key": bool(os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY"))},
        },
        "root": str(root.resolve()),
        "root_exists": root.exists(),
    }
    sys.stdout.write(json.dumps({"event": "info", **data}, ensure_ascii=False) + "\n")


@app.command()
def capture(
    title: str = typer.Argument(help="作品名（works/<title>/ に保存）"),
    max_pages: int = typer.Option(300, help="最大キャプチャページ数"),
    delay: float = typer.Option(1.0, help="ページ送り後の待機秒数"),
    key: str = typer.Option("space", help="ページ送りキー: space / left / right"),
    start: int = typer.Option(1, help="開始ページ番号（ファイル名に使用）"),
    volume: int = typer.Option(1, help="巻番号"),
    root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ"),
) -> None:
    """Kindle を前面化し、ページ送りしながらスクリーンショットを保存する"""
    from manga_dialogue.capture.base import get_driver

    work = Work(title, root, volume)
    driver = get_driver()
    reporter.event("start", f"キャプチャ開始: {work.captures_dir}", dir=str(work.captures_dir))
    try:
        saved = driver.run(
            work,
            max_pages=max_pages,
            delay=delay,
            key=key,
            start=start,
            on_page=lambda p: reporter.event("page", f"  page {p:04d}", volume=volume, page=p),
        )
    except RuntimeError as e:
        reporter.error(str(e))
        raise typer.Exit(1)
    reporter.event("done", f"完了: {saved} ページ保存", saved=saved)


def _get_model(model: str) -> VisionModel:
    try:
        return get_model(model)
    except ValueError as e:
        reporter.error(str(e))
        raise typer.Exit(1)


def _process_page(
    llm: VisionModel,
    work: Work,
    image: Path,
    book: CharacterBook,
    rename_threshold: float,
    final_book: bool = False,
) -> PageResult:
    """1ページを抽出し、台帳と出力 JSON を更新する。

    LLM が返した改名指示は confidence が閾値以上なら台帳と過去の出力に適用し、
    未満なら pending_renames.jsonl に記録するだけにする。
    """
    page = int(image.stem)
    extraction = extract_page(llm, image, book, final_book=final_book)
    added = book.merge(extraction.new_characters)
    book.save()
    result = PageResult(
        volume=work.volume,
        page=page,
        image=image.name,
        panels=extraction.panels,
        lines=extraction.lines,
        new_characters=extraction.new_characters,
        renames=extraction.renames,
        repassed=final_book,
    )
    work.output_path(page).write_text(
        json.dumps(result.model_dump(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    applied: list[dict] = []
    pending: list[dict] = []
    for r in extraction.renames:
        if book.find(r.from_name) is None:
            continue
        if r.confidence >= rename_threshold:
            n = apply_rename(work, book, r.from_name, r.to_name)
            applied.append({"from": r.from_name, "to": r.to_name, "replaced": n})
        else:
            record_pending(work, page, r)
            pending.append({"from": r.from_name, "to": r.to_name, "confidence": r.confidence})
    notes = [f"{len(extraction.lines)} lines"]
    if added:
        notes.append(f"新キャラ: {', '.join(c.name for c in added)}")
    notes += [f"改名: {a['from']} → {a['to']} ({a['replaced']} 件置換)" for a in applied]
    notes += [f"改名候補(保留): {p['from']} → {p['to']} ({p['confidence']:.2f})" for p in pending]
    reporter.event(
        "page",
        f"page {page:04d} ... " + ", ".join(notes),
        volume=work.volume,
        page=page,
        lines=len(extraction.lines),
        new_characters=[c.name for c in added],
        renames_applied=applied,
        renames_pending=pending,
        usage={"input_tokens": llm.last_usage.input_tokens, "output_tokens": llm.last_usage.output_tokens},
    )
    return result


def _usage_total(llm: VisionModel) -> dict:
    return {"input_tokens": llm.total_usage.input_tokens, "output_tokens": llm.total_usage.output_tokens}


def _abort(error: Exception, **data) -> None:
    """課金切れ・認証エラーなど、続行しても回復しない失敗で処理全体を止める"""
    reporter.error(
        f"中断: {type(error).__name__}: {str(error).splitlines()[0][:300]}\n--resume を付けて再実行すると続きから処理できます",
        error_type=type(error).__name__,
        **data,
    )
    raise typer.Exit(2)


def _report_failures(failed: list[str]) -> None:
    if not failed:
        return
    reporter.error(
        f"失敗したページ ({len(failed)}): {', '.join(failed)}\n--resume を付けて再実行すると失敗ページだけ再処理されます",
        failed=failed,
    )
    raise typer.Exit(1)


@app.command()
def extract(
    title: str = typer.Argument(help="作品名（works/<title>/captures を処理）"),
    model: str = typer.Option(DEFAULT_MODEL, help="使用するモデル ID"),
    resume: bool = typer.Option(False, help="出力済みページをスキップして再開"),
    rename_threshold: float = typer.Option(0.8, help="この confidence 以上の改名指示を自動適用"),
    volume: int = typer.Option(1, help="巻番号"),
    run: str = typer.Option(DEFAULT_RUN, help="結果を保存する run 名（モデルごとに分けるなど）"),
    from_run: str | None = typer.Option(None, help="新しい run を始めるとき、この run の台帳をコピーして使う"),
    root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ"),
) -> None:
    """キャプチャ画像を順に LLM へ送り、ページごとに JSON を出力する"""
    work = Work(title, root, volume, run)
    if from_run:
        work.init_run_from(from_run)
    images = work.capture_images()
    if not images:
        reporter.error(f"画像がありません: {work.captures_dir}")
        raise typer.Exit(1)

    work.ensure_dirs()
    book = CharacterBook.load(work.characters_path)
    llm = _get_model(model)
    _install_cancel_handlers()
    reporter.event("start", total=len(images), volume=volume)

    failed: list[str] = []
    processed = 0
    try:
        with work.locked("extract"):
            for image in images:
                if resume and work.output_path(int(image.stem)).exists():
                    continue
                _check_cancel()
                try:
                    _process_page(llm, work, image, book, rename_threshold)
                    processed += 1
                except ExtractionFailed as e:
                    reporter.event("page_failed", f"失敗（スキップ）: {e}", volume=volume, page=int(image.stem), message=str(e))
                    failed.append(image.name)
                except Exception as e:
                    _abort(e, done=processed, failed=failed, usage=_usage_total(llm))
    except RunLocked as e:
        _locked_exit(e)
    except Cancelled:
        _cancelled_exit(done=processed, failed=failed, usage=_usage_total(llm))

    reporter.event(
        "done", f"完了: {work.output_dir} / 台帳 {len(book.characters)} 名",
        processed=processed, characters=len(book.characters), failed=failed, usage=_usage_total(llm),
    )
    _report_failures(failed)


@app.command()
def repass(
    title: str = typer.Argument(help="作品名"),
    model: str = typer.Option(DEFAULT_MODEL, help="使用するモデル ID"),
    min_confidence: float = typer.Option(0.5, help="この値未満の confidence を含むページを再抽出"),
    all_pages: bool = typer.Option(False, "--all", help="条件に関係なく全ページを再抽出"),
    pages: list[int] = typer.Option([], "--page", help="指定ページだけ再抽出（複数指定可）"),
    force: bool = typer.Option(False, help="手動修正済み（manual）のページも再抽出する"),
    dry_run: bool = typer.Option(False, help="対象ページの一覧だけ表示して終了"),
    rename_threshold: float = typer.Option(0.8, help="この confidence 以上の改名指示を自動適用"),
    volume: int | None = typer.Option(None, help="巻番号（省略時は全巻）"),
    run: str = typer.Option(DEFAULT_RUN, help="結果を保存する run 名（モデルごとに分けるなど）"),
    root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ"),
) -> None:
    """処理済み範囲の台帳を使い、「不明」や低 confidence を含むページだけ再抽出する

    extract を最後まで通した後に実行する。対象ページの出力 JSON は上書きされる。
    手動修正済みのページは --force を付けない限りスキップする。
    """
    work = Work(title, root, run=run)
    book = CharacterBook.load(work.characters_path)
    if not book.characters:
        reporter.error(f"台帳が空です。先に extract を実行してください: {work.characters_path}")
        raise typer.Exit(1)

    volumes = [work.with_volume(volume)] if volume is not None else work.all_volumes()
    targets: list[tuple[Work, Path]] = []
    skipped_manual: list[str] = []
    for vol in volumes:
        for image in vol.capture_images():
            out = vol.output_path(int(image.stem))
            if not out.exists():
                continue
            page = int(image.stem)
            result = PageResult.model_validate_json(out.read_text(encoding="utf-8"))
            if pages:
                selected = page in pages
            else:
                selected = all_pages or result.needs_repass(min_confidence)
            if not selected:
                continue
            if result.is_locked() and not force:
                skipped_manual.append(f"v{vol.volume:02d}/{image.name}")
                continue
            targets.append((vol, image))

    reporter.event(
        "start",
        f"再抽出対象: {len(targets)} ページ（台帳 {len(book.characters)} 名）"
        + (f"、手動修正済みのためスキップ: {len(skipped_manual)}" if skipped_manual else ""),
        total=len(targets),
        skipped_manual=skipped_manual,
        targets=[{"volume": v.volume, "page": int(t.stem)} for v, t in targets],
    )
    if dry_run or not targets:
        for vol, t in targets:
            reporter.event("target", f"  v{vol.volume:02d} {t.name}", volume=vol.volume, page=int(t.stem))
        return

    llm = _get_model(model)
    _install_cancel_handlers()
    failed: list[str] = []
    processed = 0
    try:
        with work.locked("repass"):
            for vol, image in targets:
                _check_cancel()
                try:
                    _process_page(llm, vol, image, book, rename_threshold, final_book=True)
                    processed += 1
                except ExtractionFailed as e:
                    reporter.event("page_failed", f"失敗（スキップ）: {e}", volume=vol.volume, page=int(image.stem), message=str(e))
                    failed.append(f"v{vol.volume:02d}/{image.name}")
                except Exception as e:
                    _abort(e, done=processed, failed=failed, usage=_usage_total(llm))
    except RunLocked as e:
        _locked_exit(e)
    except Cancelled:
        _cancelled_exit(done=processed, failed=failed, usage=_usage_total(llm))

    reporter.event("done", f"完了: {processed} ページ再抽出", processed=processed, failed=failed, usage=_usage_total(llm))
    _report_failures(failed)


@app.command()
def consolidate(
    title: str = typer.Argument(help="作品名"),
    model: str = typer.Option(DEFAULT_MODEL, help="使用するモデル ID"),
    rename_threshold: float = typer.Option(0.8, help="この confidence 以上の提案を自動適用"),
    dry_run: bool = typer.Option(False, help="提案を表示するだけで適用しない"),
    run: str = typer.Option(DEFAULT_RUN, help="結果を保存する run 名（モデルごとに分けるなど）"),
    root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ"),
) -> None:
    """全セリフを通読させて仮名の解決・重複統合を提案させ、台帳と出力に適用する

    画像は送らずテキストのみで 1 回だけ API を呼ぶ。extract / repass の実行中には使わない。
    """
    work = Work(title, root, run=run)
    book = CharacterBook.load(work.characters_path)
    if not book.characters or not any(v.output_files() for v in work.all_volumes()):
        reporter.error("台帳または出力がありません。先に extract を実行してください")
        raise typer.Exit(1)

    llm = _get_model(model)
    try:
        plan = propose_consolidation(llm, book, work)
    except Exception as e:
        _abort(e)
    reporter.event("start", f"提案: {len(plan.renames)} 件", total=len(plan.renames), usage=_usage_total(llm))
    applied = 0
    try:
        with work.locked("consolidate"):
            _apply_consolidation(work, book, plan, rename_threshold, dry_run)
    except RunLocked as e:
        _locked_exit(e)


def _apply_consolidation(work: Work, book: CharacterBook, plan, rename_threshold: float, dry_run: bool) -> None:
    applied = 0
    for r in plan.renames:
        known = book.find(r.from_name) is not None
        will_apply = not dry_run and known and r.confidence >= rename_threshold
        mark = "候補" if dry_run else ("適用" if will_apply else "保留")
        replaced = None
        if will_apply:
            replaced = apply_rename(work, book, r.from_name, r.to_name)
            applied += 1
        elif not dry_run and known:
            record_pending(work, 0, r)
        text = f"  [{mark} {r.confidence:.2f}] {r.from_name} → {r.to_name}\n      {r.reason}"
        if replaced is not None:
            text += f"\n      → {replaced} 件置換"
        reporter.event(
            "proposal", text, status=mark, from_name=r.from_name, to_name=r.to_name,
            confidence=r.confidence, reason=r.reason, replaced=replaced,
        )
    reporter.event("done", "" if dry_run else f"完了: {applied} 件適用 / 台帳 {len(book.characters)} 名", applied=applied, characters=len(book.characters))


@app.command()
def rename(
    title: str = typer.Argument(help="作品名"),
    from_name: str = typer.Argument(help="台帳にある現在の名前（仮名など）"),
    to_name: str = typer.Argument(help="新しい名前"),
    run: str = typer.Option(DEFAULT_RUN, help="結果を保存する run 名（モデルごとに分けるなど）"),
    root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ"),
) -> None:
    """台帳のキャラを手動で改名し、出力済み JSON の speaker も置き換える"""
    work = Work(title, root, run=run)
    book = CharacterBook.load(work.characters_path)
    if book.find(from_name) is None:
        reporter.error(f"台帳に見つかりません: {from_name}")
        raise typer.Exit(1)
    try:
        with work.locked("rename"):
            n = apply_rename(work, book, from_name, to_name)
    except RunLocked as e:
        _locked_exit(e)
    reporter.event("done", f"改名: {from_name} → {to_name} / 出力 {n} 件置換 / 台帳 {len(book.characters)} 名", replaced=n, characters=len(book.characters))


@app.command("export")
def export_cmd(
    title: str = typer.Argument(help="作品名"),
    fmt: str = typer.Option("csv", "--format", help="csv / tsv / markdown"),
    dest: Path | None = typer.Option(None, "--out", help="出力先ファイル（省略時は works/<作品名>/ 直下）"),
    volume: int | None = typer.Option(None, help="巻番号（省略時は全巻）"),
    run: str = typer.Option(DEFAULT_RUN, help="結果を保存する run 名（モデルごとに分けるなど）"),
    root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ"),
) -> None:
    """抽出結果を CSV / TSV / Markdown に書き出す"""
    if fmt not in FORMATS:
        reporter.error(f"未対応の形式: {fmt}（csv / tsv / markdown）")
        raise typer.Exit(1)
    work = Work(title, root, run=run)
    path, rows = export(work, fmt, dest, volume)
    reporter.event("done", f"書き出し: {path} ({rows} 行)", path=str(path), rows=rows)


@app.command()
def fix(
    title: str = typer.Argument(help="作品名"),
    instruction: str | None = typer.Option(None, "--instruction", "-i", help="修正の指示文"),
    volume: int | None = typer.Option(None, help="巻番号（省略時は全巻）"),
    pages: list[int] = typer.Option([], "--page", help="対象ページ（複数指定可。省略時は範囲内の全ページ）"),
    with_images: bool = typer.Option(False, help="対象ページの画像も添付する（費用増）"),
    apply: bool = typer.Option(False, help="変更案を適用する（省略時は提案のみ）"),
    apply_from: Path | None = typer.Option(None, "--apply-from", help="変更案の JSON（{\"changes\": [...]}）を読み込んで適用する。API は呼ばない"),
    model: str = typer.Option(DEFAULT_MODEL, help="使用するモデル ID"),
    run: str = typer.Option(DEFAULT_RUN, help="結果を保存する run 名（モデルごとに分けるなど）"),
    root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ"),
) -> None:
    """指示文に基づいて抽出結果の一括修正案を作り、必要なら適用する

    適用した行には manual が付き、以降の repass で上書きされなくなる。
    """
    work = Work(title, root, run=run)
    if apply_from is not None:
        plan = FixPlan.model_validate_json(apply_from.read_text(encoding="utf-8"))
        try:
            with work.locked("fix"):
                applied = apply_changes(work, plan.changes)
        except RunLocked as e:
            _locked_exit(e)
        reporter.event("done", f"完了: {applied} 件適用", applied=applied, proposed=len(plan.changes))
        return
    if not instruction:
        reporter.error("--instruction（指示文）または --apply-from を指定してください")
        raise typer.Exit(1)

    book = CharacterBook.load(work.characters_path)
    targets = load_pages(work, volume, pages)
    if not targets:
        reporter.error("対象ページがありません")
        raise typer.Exit(1)

    llm = _get_model(model)
    try:
        plan = propose_fix(llm, book, targets, instruction, with_images=with_images)
    except Exception as e:
        _abort(e)
    reporter.event("start", f"変更案: {len(plan.changes)} 件（対象 {len(targets)} ページ）", total=len(plan.changes), pages=len(targets))
    by_page = {(v.volume, r.page): r for v, r in targets}
    for c in plan.changes:
        result = by_page.get((c.volume, c.page))
        before = result.lines[c.index] if result and 0 <= c.index < len(result.lines) else None
        desc = f"  v{c.volume:02d} p{c.page:03d} #{c.index}"
        if before:
            desc += f" 「{before.text[:20]}」"
        for field in ("speaker", "text", "panel"):
            new = getattr(c, field)
            if new is not None:
                old = getattr(before, field) if before else "?"
                desc += f"\n      {field}: {old} → {new}"
        desc += f"\n      {c.reason}"
        reporter.event(
            "change", desc, volume=c.volume, page=c.page, index=c.index,
            before=before.model_dump() if before else None,
            speaker=c.speaker, text=c.text, panel=c.panel, reason=c.reason,
        )
    applied = 0
    if apply:
        try:
            with work.locked("fix"):
                applied = apply_changes(work, plan.changes)
        except RunLocked as e:
            _locked_exit(e)
    reporter.event(
        "done", f"完了: {applied} 件適用" if apply else "（--apply で適用）",
        applied=applied, proposed=len(plan.changes), usage=_usage_total(llm),
    )


def _pending_event(item: PendingRename, book: CharacterBook, event: str = "pending") -> None:
    """applicable: from_name がまだ台帳にあり、承認すれば rename が実行できる"""
    applicable = book.find(item.from_name) is not None
    note = "" if applicable else "  ※ 台帳に from_name がありません（既に統合済み）"
    text = f"  [{item.status} {item.confidence:.2f}] {item.id}  {item.from_name} → {item.to_name}  ({len(item.sources)} 件の提案){note}\n      {item.reason}"
    reporter.event(
        event, text, id=item.id, from_name=item.from_name, to_name=item.to_name, status=item.status,
        confidence=item.confidence, reason=item.reason, updated_at=item.updated_at, applicable=applicable,
        sources=[{"volume": x.volume, "page": x.page, "confidence": x.confidence, "reason": x.reason, "at": x.at} for x in item.sources],
    )


@pending_app.command("list")
def pending_list(
    title: str = typer.Argument(help="作品名"),
    all_items: bool = typer.Option(False, "--all", help="承認・却下済みも表示"),
    run: str = typer.Option(DEFAULT_RUN, help="run 名"),
    root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ"),
) -> None:
    """保留中の改名候補を一覧表示する"""
    work = Work(title, root, run=run)
    store = PendingStore.load(work.pending_renames_path)
    book = CharacterBook.load(work.characters_path)
    items = store.list(None if all_items else "pending")
    reporter.event("start", f"改名候補: {len(items)} 件", total=len(items))
    for item in items:
        _pending_event(item, book)
    reporter.event("done", "", total=len(items))


def _pending_set(title: str, run: str, root: Path, item_id: str, status: str) -> None:
    work = Work(title, root, run=run)
    store = PendingStore.load(work.pending_renames_path)
    item = store.get(item_id)
    if item is None:
        reporter.error(f"候補が見つかりません: {item_id}")
        raise typer.Exit(1)
    replaced = 0
    book = CharacterBook.load(work.characters_path)
    if status == "approved" and book.find(item.from_name) is not None:
        try:
            with work.locked("pending approve"):
                replaced = apply_rename(work, book, item.from_name, item.to_name)
        except RunLocked as e:
            _locked_exit(e)
    item = store.set_status(item_id, status)
    _pending_event(item, book, event="updated")
    reporter.event("done", f"{item.from_name} → {item.to_name}: {status}" + (f" / 出力 {replaced} 件置換" if status == "approved" else ""), id=item_id, status=status, replaced=replaced)


@pending_app.command("approve")
def pending_approve(
    title: str = typer.Argument(help="作品名"),
    item_id: str = typer.Argument(help="候補の id"),
    run: str = typer.Option(DEFAULT_RUN, help="run 名"),
    root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ"),
) -> None:
    """候補を承認し、rename を実行して台帳と出力に反映する"""
    _pending_set(title, run, root, item_id, "approved")


@pending_app.command("reject")
def pending_reject(
    title: str = typer.Argument(help="作品名"),
    item_id: str = typer.Argument(help="候補の id"),
    run: str = typer.Option(DEFAULT_RUN, help="run 名"),
    root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ"),
) -> None:
    """候補を却下する（同じ組が再提案されても保留に戻らない）"""
    _pending_set(title, run, root, item_id, "rejected")


@pending_app.command("reopen")
def pending_reopen(
    title: str = typer.Argument(help="作品名"),
    item_id: str = typer.Argument(help="候補の id"),
    run: str = typer.Option(DEFAULT_RUN, help="run 名"),
    root: Path = typer.Option(DEFAULT_ROOT, help="作品ルートディレクトリ"),
) -> None:
    """却下した候補を保留に戻す"""
    _pending_set(title, run, root, item_id, "pending")


if __name__ == "__main__":
    app()
