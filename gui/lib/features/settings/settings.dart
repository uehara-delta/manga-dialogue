/// アプリ設定。ホームディレクトリ直下の JSON に保存する。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../engine/engine_locator.dart';

class Settings {
  Settings({
    required this.worksRoot,
    String? engineCommand,
    this.engineWorkingDir,
    Map<String, String>? apiKeys,
    Map<String, String>? lastRun,
    this.defaultModel = 'gemini-3.7-flash',
    this.captureKey = 'space',
    this.captureDelay = 1.5,
    this.uiScale = 1.0,
    Map<String, double>? layout,
  })  : engineCommand = engineCommand ?? EngineLocator.defaultCommand(),
        apiKeys = apiKeys ?? {},
        lastRun = lastRun ?? {},
        layout = layout ?? {};

  /// 作品データのルート（既定はアプリ起動ディレクトリ直下の works）
  String worksRoot;

  /// エンジンの起動コマンド（同梱バイナリがあればそのパス、開発時は uv 経由）
  String engineCommand;

  /// エンジンを起動する作業ディレクトリ（uv run の場合はリポジトリ）
  String? engineWorkingDir;

  /// エンジンに環境変数として渡す API キー（ANTHROPIC_API_KEY / GEMINI_API_KEY）。
  /// 空のものは渡さない（.env や親プロセスの環境変数が使われる）
  Map<String, String> apiKeys;

  Map<String, String> get environment => {for (final e in apiKeys.entries) if (e.value.trim().isNotEmpty) e.key: e.value.trim()};

  /// 作品ごとに最後に開いた run（抽出データ）
  Map<String, String> lastRun;

  /// 抽出に使う既定モデル
  String defaultModel;

  /// キャプチャの既定設定
  String captureKey;
  double captureDelay;

  /// 文字の大きさ（1.0 が標準）
  double uiScale;

  /// 画面ごとの分割位置など（例: editor.split = 画像側の幅の割合）
  Map<String, double> layout;

  /// 既定 works の親。開発時はリポジトリ直下、配布時はアプリと同じ階層（macOS は .app の隣、Windows は exe のフォルダ）
  static String _appDir() {
    if (EngineLocator.bundledPath() == null) {
      final repo = EngineLocator.repoRoot();
      if (repo != null) return repo;
    }
    final exe = Platform.resolvedExecutable;
    if (Platform.isMacOS) {
      final contents = p.dirname(p.dirname(exe));
      if (p.basename(contents) == 'Contents') return p.dirname(p.dirname(contents));
    }
    return Directory.current.path == '/' ? p.dirname(exe) : Directory.current.path;
  }

  static String get _path {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    return p.join(home, '.manga_dialogue_gui.json');
  }

  static Settings load() {
    final f = File(_path);
    if (f.existsSync()) {
      try {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        return Settings(
          worksRoot: j['worksRoot'] as String,
          engineCommand: j['engineCommand'] as String?,
          engineWorkingDir: j['engineWorkingDir'] as String?,
          apiKeys: {for (final e in (j['apiKeys'] as Map<String, dynamic>? ?? {}).entries) e.key: e.value as String},
          lastRun: {for (final e in (j['lastRun'] as Map<String, dynamic>? ?? {}).entries) e.key: e.value as String},
          defaultModel: j['defaultModel'] as String? ?? 'gemini-3.7-flash',
          captureKey: j['captureKey'] as String? ?? 'space',
          captureDelay: (j['captureDelay'] as num?)?.toDouble() ?? 1.5,
          uiScale: (j['uiScale'] as num?)?.toDouble() ?? 1.0,
          layout: {for (final e in (j['layout'] as Map<String, dynamic>? ?? {}).entries) e.key: (e.value as num).toDouble()},
        );
      } catch (_) {}
    }
    return Settings(worksRoot: p.join(_appDir(), 'works'));
  }

  void save() {
    File(_path).writeAsStringSync(jsonEncode({
      'worksRoot': worksRoot,
      'engineCommand': engineCommand,
      'engineWorkingDir': engineWorkingDir,
      'apiKeys': apiKeys,
      'lastRun': lastRun,
      'defaultModel': defaultModel,
      'captureKey': captureKey,
      'captureDelay': captureDelay,
      'uiScale': uiScale,
      'layout': layout,
    }));
  }
}
