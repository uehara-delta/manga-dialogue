/// アプリ設定。ホームディレクトリ直下の JSON に保存する。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class Settings {
  Settings({required this.worksRoot, this.engineCommand = 'uv run --env-file .env manga-dialogue', this.engineWorkingDir});

  /// 作品データのルート（既定はアプリ起動ディレクトリ直下の works）
  String worksRoot;

  /// エンジンの起動コマンド（開発時は uv 経由、配布時は同梱バイナリ）
  String engineCommand;

  /// エンジンを起動する作業ディレクトリ（uv run の場合はリポジトリ）
  String? engineWorkingDir;

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
          engineCommand: j['engineCommand'] as String? ?? 'uv run --env-file .env manga-dialogue',
          engineWorkingDir: j['engineWorkingDir'] as String?,
        );
      } catch (_) {}
    }
    return Settings(worksRoot: p.join(Directory.current.path, 'works'));
  }

  void save() {
    File(_path).writeAsStringSync(jsonEncode({
      'worksRoot': worksRoot,
      'engineCommand': engineCommand,
      'engineWorkingDir': engineWorkingDir,
    }));
  }
}
