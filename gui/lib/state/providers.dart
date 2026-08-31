import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/settings.dart';
import '../models/models.dart';
import '../workspace/workspace.dart';

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() => Settings.load();

  void update(void Function(Settings s) edit) {
    final s = Settings(worksRoot: state.worksRoot, engineCommand: state.engineCommand, engineWorkingDir: state.engineWorkingDir, apiKeys: Map.of(state.apiKeys));
    edit(s);
    s.save();
    state = s;
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

final workspaceProvider = Provider<Workspace>((ref) => Workspace(ref.watch(settingsProvider).worksRoot));

/// 作品一覧。refresh で再走査する
class WorksNotifier extends Notifier<List<WorkSummary>> {
  @override
  List<WorkSummary> build() => ref.watch(workspaceProvider).listWorks();
  void refresh() => state = ref.read(workspaceProvider).listWorks();
}

final worksProvider = NotifierProvider<WorksNotifier, List<WorkSummary>>(WorksNotifier.new);

/// 現在開いている run の台帳
class CharactersNotifier extends Notifier<List<Character>> {
  @override
  List<Character> build() => [];

  void load(String title, String run) => state = ref.read(workspaceProvider).loadCharacters(title, run);

  void save(String title, String run, List<Character> characters) {
    ref.read(workspaceProvider).saveCharacters(title, run, characters);
    state = List.of(characters);
  }
}

final charactersProvider = NotifierProvider<CharactersNotifier, List<Character>>(CharactersNotifier.new);

/// ページ編集の状態。ページ JSON をメモリに持ち、編集のたびに保存する
class PageEditorState {
  const PageEditorState({required this.ref, required this.pages, this.result, this.selected, this.undo});
  final PageRef ref;
  final List<int> pages;
  final PageResult? result;
  final int? selected;
  final PageResult? undo;

  int get index => pages.indexOf(ref.page);
  bool get hasPrev => index > 0;
  bool get hasNext => index >= 0 && index < pages.length - 1;

  PageEditorState copyWith({PageRef? ref, List<int>? pages, PageResult? result, int? selected, PageResult? undo, bool clearSelection = false}) =>
      PageEditorState(
        ref: ref ?? this.ref,
        pages: pages ?? this.pages,
        result: result ?? this.result,
        selected: clearSelection ? null : (selected ?? this.selected),
        undo: undo ?? this.undo,
      );
}

class PageEditorNotifier extends Notifier<PageEditorState?> {
  @override
  PageEditorState? build() => null;

  Workspace get _ws => ref.read(workspaceProvider);

  void open(PageRef r) {
    final pages = _ws.listPages(r.title, r.volume);
    final page = pages.contains(r.page) ? r.page : (pages.isEmpty ? r.page : pages.first);
    final target = r.copyWith(page: page);
    ref.read(charactersProvider.notifier).load(r.title, r.run);
    state = PageEditorState(ref: target, pages: pages, result: _ws.loadPage(target));
  }

  void goTo(int page) {
    final s = state;
    if (s == null) return;
    final target = s.ref.copyWith(page: page);
    state = PageEditorState(ref: target, pages: s.pages, result: _ws.loadPage(target));
  }

  void prev() { final s = state; if (s != null && s.hasPrev) goTo(s.pages[s.index - 1]); }
  void next() { final s = state; if (s != null && s.hasNext) goTo(s.pages[s.index + 1]); }

  void select(int? i) => state = state?.copyWith(selected: i, clearSelection: i == null);

  /// 編集を適用して保存する。変更前の状態を 1 段だけ Undo 用に保持。
  /// apply が選択行を変えた場合（追加・削除・並べ替え）はそれを引き継ぐ
  void edit(void Function(PageResult r) apply) {
    final s = state;
    final r = s?.result;
    if (s == null || r == null) return;
    final before = PageResult.fromJson(r.toJson());
    apply(r);
    _ws.savePage(s.ref, r);
    final current = state ?? s;
    state = PageEditorState(ref: s.ref, pages: s.pages, result: r, selected: current.selected, undo: before);
  }

  void editLine(int i, void Function(Line l) apply) => edit((r) {
        if (i < 0 || i >= r.lines.length) return;
        apply(r.lines[i]);
        r.lines[i].manual = true;
      });

  void addLine({double? x, double? y}) {
    final s = state;
    if (s?.result == null) return;
    edit((r) {
      final sel = s!.selected;
      final panel = sel != null && sel < r.lines.length ? r.lines[sel].panel : (r.lines.isEmpty ? 1 : r.lines.last.panel);
      final line = Line(panel: panel, speaker: '不明', text: '', confidence: 1.0, basis: 'unknown', x: x, y: y, manual: true);
      final at = sel != null ? sel + 1 : r.lines.length;
      r.lines.insert(at, line);
      state = state!.copyWith(selected: at);
    });
  }

  void removeLine(int i) => edit((r) {
        if (i < 0 || i >= r.lines.length) return;
        r.lines.removeAt(i);
        if (r.lines.isEmpty) {
          state = state!.copyWith(clearSelection: true);
        } else {
          state = state!.copyWith(selected: i.clamp(0, r.lines.length - 1));
        }
      });

  void moveLine(int from, int to) => edit((r) {
        if (from < 0 || from >= r.lines.length || to < 0 || to >= r.lines.length) return;
        final l = r.lines.removeAt(from);
        l.manual = true;
        r.lines.insert(to, l);
        state = state!.copyWith(selected: to);
      });

  void setPageManual(bool v) => edit((r) => r.manual = v);

  void undo() {
    final s = state;
    final u = s?.undo;
    if (s == null || u == null) return;
    _ws.savePage(s.ref, u);
    state = PageEditorState(ref: s.ref, pages: s.pages, result: u, selected: null);
  }
}

final pageEditorProvider = NotifierProvider<PageEditorNotifier, PageEditorState?>(PageEditorNotifier.new);
