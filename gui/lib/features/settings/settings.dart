/// アプリ設定。ホームディレクトリ直下の JSON に保存する。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../engine/engine_locator.dart';

class Settings {
  Settings({required this.worksRoot, String? engineCommand, this.engineWorkingDir, Map<String, String>? apiKeys})
      : engineCommand = engineCommand ?? EngineLocator.defaultCommand(),
        apiKeys = apiKeys ?? {};

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

  /// 配布時の既定 works: アプリと同じ階層（macOS は .app の隣、Windows は exe のフォルダ）
  static String _appDir() {
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
    }));
  }
}
