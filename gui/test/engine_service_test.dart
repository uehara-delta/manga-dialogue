import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manga_dialogue_gui/engine/engine_service.dart';
import 'package:path/path.dart' as p;

/// リポジトリの CLI を実際に起動する統合テスト。uv とリポジトリが必要。
void main() {
  final repo = p.normalize(p.join(Directory.current.path, '..'));
  final service = EngineService(EngineConfig(
    command: 'uv run --env-file .env manga-dialogue',
    workingDir: repo,
    worksRoot: p.join(repo, 'works'),
  ));

  test('info returns engine metadata', () async {
    final info = await service.info();
    expect(info, isNotNull);
    expect(info!['event'], 'info');
    expect(info['default_model'], isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a failing command yields a failed job with an error event', () async {
    final job = await service.start(['export', '存在しない作品', '--format', 'xlsx'], label: 'bad export');
    await job.stream.drain<void>();
    expect(job.status, JobStatus.failed);
    expect(job.events.any((e) => e.type == 'error'), isTrue);
    expect(job.errorMessage, contains('未対応'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
