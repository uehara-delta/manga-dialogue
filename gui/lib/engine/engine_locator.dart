import 'dart:io';

import 'package:path/path.dart' as p;

/// アプリに同梱されたエンジンの場所。
/// - macOS: `<App>.app/Contents/Resources/engine/manga-dialogue-engine`
/// - Windows: `<exe のフォルダ>/engine/manga-dialogue-engine.exe`
class EngineLocator {
  static String? bundledPath() {
    final exe = Platform.resolvedExecutable;
    final String candidate;
    if (Platform.isMacOS) {
      // Contents/MacOS/<exe> → Contents/Resources/engine/
      candidate = p.join(p.dirname(p.dirname(exe)), 'Resources', 'engine', 'manga-dialogue-engine');
    } else if (Platform.isWindows) {
      candidate = p.join(p.dirname(exe), 'engine', 'manga-dialogue-engine.exe');
    } else {
      candidate = p.join(p.dirname(exe), 'engine', 'manga-dialogue-engine');
    }
    return File(candidate).existsSync() ? candidate : null;
  }

  /// 同梱エンジンがあればそのパス、なければ開発用の uv コマンド
  static String defaultCommand() => bundledPath() ?? 'uv run --env-file .env manga-dialogue';
}
