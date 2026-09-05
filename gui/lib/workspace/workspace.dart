/// works/ ディレクトリの走査と JSON の読み書き。エンジンと同じ構成規則に従う。
///
/// - `works/<title>/volumes/<NN>/captures/NNNN.png`
/// - `works/<title>/runs/<run>/characters.json`
/// - `works/<title>/runs/<run>/volumes/<NN>/output/NNNN.json`
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/models.dart';

class WorkSummary {
  WorkSummary({required this.title, required this.volumes, required this.runs, required this.modified});
  final String title;
  final List<int> volumes;
  final List<String> runs;
  final DateTime modified;
}

class PageRef {
  const PageRef({required this.title, required this.run, required this.volume, required this.page});
  final String title;
  final String run;
  final int volume;
  final int page;

  PageRef copyWith({String? title, String? run, int? volume, int? page}) =>
      PageRef(title: title ?? this.title, run: run ?? this.run, volume: volume ?? this.volume, page: page ?? this.page);

  @override
  bool operator ==(Object other) =>
      other is PageRef && other.title == title && other.run == run && other.volume == volume && other.page == page;
  @override
  int get hashCode => Object.hash(title, run, volume, page);
}

class Workspace {
  Workspace(this.root);
  final String root;

  static const _encoder = JsonEncoder.withIndent('  ');

  String workDir(String title) => p.join(root, title);
  String capturesDir(String title, int volume) => p.join(workDir(title), 'volumes', _nn(volume), 'captures');
  String runDir(String title, String run) => p.join(workDir(title), 'runs', run);
  String outputDir(String title, String run, int volume) => p.join(runDir(title, run), 'volumes', _nn(volume), 'output');
  String charactersPath(String title, String run) => p.join(runDir(title, run), 'characters.json');
  String lockPath(String title, String run) => p.join(runDir(title, run), '.lock');
  String candidatesPath(String title, String run) => p.join(runDir(title, run), 'candidates.json');
  String capturePath(PageRef r) => p.join(capturesDir(r.title, r.volume), '${_nnnn(r.page)}.png');
  String outputPath(PageRef r) => p.join(outputDir(r.title, r.run, r.volume), '${_nnnn(r.page)}.json');

  static String _nn(int v) => v.toString().padLeft(2, '0');
  static String _nnnn(int v) => v.toString().padLeft(4, '0');

  List<WorkSummary> listWorks() {
    final dir = Directory(root);
    if (!dir.existsSync()) return [];
    final works = <WorkSummary>[];
    for (final e in dir.listSync().whereType<Directory>()) {
      final title = p.basename(e.path);
      if (title.startsWith('.')) continue;
      works.add(WorkSummary(
        title: title,
        volumes: listVolumes(title),
        runs: listRuns(title),
        modified: e.statSync().modified,
      ));
    }
    works.sort((a, b) => b.modified.compareTo(a.modified));
    return works;
  }

  List<int> listVolumes(String title) {
    final dir = Directory(p.join(workDir(title), 'volumes'));
    if (!dir.existsSync()) return [];
    final nums = [
      for (final d in dir.listSync().whereType<Directory>())
        if (int.tryParse(p.basename(d.path)) != null) int.parse(p.basename(d.path))
    ];
    nums.sort();
    return nums;
  }

  /// run（抽出結果）の一覧。最近更新されたものが先頭
  List<String> listRuns(String title) {
    final dir = Directory(p.join(workDir(title), 'runs'));
    if (!dir.existsSync()) return [];
    final dirs = dir.listSync().whereType<Directory>().toList();
    DateTime modified(Directory d) {
      final book = File(p.join(d.path, 'characters.json'));
      return (book.existsSync() ? book : d).statSync().modified;
    }
    dirs.sort((a, b) => modified(b).compareTo(modified(a)));
    return [for (final d in dirs) p.basename(d.path)];
  }

  /// キャプチャ画像のあるページ番号（抽出結果の有無は問わない）
  List<int> listPages(String title, int volume) {
    final dir = Directory(capturesDir(title, volume));
    if (!dir.existsSync()) return [];
    final pages = [
      for (final f in dir.listSync().whereType<File>())
        if (f.path.endsWith('.png') && int.tryParse(p.basenameWithoutExtension(f.path)) != null)
          int.parse(p.basenameWithoutExtension(f.path))
    ];
    pages.sort();
    return pages;
  }

  bool isLocked(String title, String run) => File(lockPath(title, run)).existsSync();

  /// run × 巻 の抽出済みページ数
  int countOutputs(String title, String run, int volume) {
    final dir = Directory(outputDir(title, run, volume));
    if (!dir.existsSync()) return 0;
    return dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).length;
  }

  /// ディレクトリの合計サイズ（バイト）
  int dirSize(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return 0;
    var total = 0;
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      total += f.lengthSync();
    }
    return total;
  }

  /// キャプチャ 1 ページを削除する。全 run の対応する抽出結果も消す
  void deleteCapturePage(String title, int volume, int page) {
    final png = File(p.join(capturesDir(title, volume), '${_nnnn(page)}.png'));
    if (png.existsSync()) png.deleteSync();
    for (final run in listRuns(title)) {
      final out = File(p.join(outputDir(title, run, volume), '${_nnnn(page)}.json'));
      if (out.existsSync()) out.deleteSync();
    }
  }

  /// 巻のキャプチャと全 run の抽出結果を削除する
  void deleteVolume(String title, int volume) {
    final dir = Directory(p.join(workDir(title), 'volumes', _nn(volume)));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    for (final run in listRuns(title)) {
      final out = Directory(p.join(runDir(title, run), 'volumes', _nn(volume)));
      if (out.existsSync()) out.deleteSync(recursive: true);
    }
  }

  /// run（台帳と全巻の抽出結果）を削除する
  void deleteRun(String title, String run) {
    final dir = Directory(runDir(title, run));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  /// 作品全体を削除する
  void deleteWork(String title) {
    final dir = Directory(workDir(title));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  PageResult? loadPage(PageRef r) {
    final f = File(outputPath(r));
    if (!f.existsSync()) return null;
    return PageResult.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
  }

  void savePage(PageRef r, PageResult result) {
    final f = File(outputPath(r));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('${_encoder.convert(result.toJson())}\n');
  }

  List<Character> loadCharacters(String title, String run) {
    final f = File(charactersPath(title, run));
    if (!f.existsSync()) return [];
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return [for (final c in (j['characters'] as List)) Character.fromJson(c as Map<String, dynamic>)];
  }

  void saveCharacters(String title, String run, List<Character> characters) {
    final f = File(charactersPath(title, run));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('${_encoder.convert({'characters': [for (final c in characters) c.toJson()]})}\n');
  }

  /// run.json に記録されたモデル。なければ run 名がモデル ID の形ならそれ、それも違えば null
  String? runModel(String title, String run) {
    final f = File(p.join(runDir(title, run), 'run.json'));
    if (f.existsSync()) {
      try {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final m = j['model'] as String?;
        if (m != null && m.isNotEmpty) return m;
      } catch (_) {}
    }
    for (final prefix in const ['claude-', 'gemini-', 'gpt-']) {
      if (run.startsWith(prefix)) return run;
    }
    return null;
  }

  List<Candidate> loadCandidates(String title, String run) {
    final f = File(candidatesPath(title, run));
    if (!f.existsSync()) return [];
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return [for (final c in (j['candidates'] as List? ?? [])) Candidate.fromJson(c as Map<String, dynamic>)];
  }

  void saveCandidates(String title, String run, List<Candidate> candidates) {
    final f = File(candidatesPath(title, run));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('${_encoder.convert({'candidates': [for (final c in candidates) c.toJson()]})}\n');
  }

  /// run 内の全ページを走査して話者ごとのセリフ数を数える
  Map<String, int> speakerCounts(String title, String run) {
    final counts = <String, int>{};
    for (final v in listVolumes(title)) {
      final dir = Directory(outputDir(title, run, v));
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.json')) continue;
        final r = PageResult.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
        for (final l in r.lines) {
          counts[l.speaker] = (counts[l.speaker] ?? 0) + 1;
        }
      }
    }
    return counts;
  }
}
