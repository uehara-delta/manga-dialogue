import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine_locator.dart';
import '../engine/engine_service.dart';
import '../features/settings/settings.dart';
import 'providers.dart';

EngineConfig _configFrom(Settings s) => EngineConfig(
      command: s.engineCommand,
      workingDir: s.engineWorkingDir ?? EngineLocator.defaultWorkingDir(),
      worksRoot: s.worksRoot,
      environment: s.environment,
    );

/// EngineService はアプリで 1 つ。設定が変わってもサービスは作り直さず、
/// 次回のプロセス起動から新しい設定を使う（作り直すと実行中のジョブ一覧が消える）
final engineServiceProvider = Provider<EngineService>((ref) {
  final service = EngineService(_configFrom(ref.read(settingsProvider)));
  ref.listen(settingsProvider, (_, s) => service.config = _configFrom(s));
  ref.onDispose(() {
    for (final j in service.jobs) {
      service.cancel(j);
    }
  });
  return service;
});

/// ジョブ一覧。EngineService の変更通知を state に写す
class JobsNotifier extends Notifier<List<Job>> {
  StreamSubscription<List<Job>>? _sub;

  @override
  List<Job> build() {
    final service = ref.watch(engineServiceProvider);
    _sub?.cancel();
    _sub = service.changes.listen((jobs) => state = jobs);
    ref.onDispose(() => _sub?.cancel());
    return List.unmodifiable(service.jobs);
  }

  Future<Job> start(List<String> args, {required String label, String? run}) =>
      ref.read(engineServiceProvider).start(args, label: label, run: run);

  void cancel(Job job) => ref.read(engineServiceProvider).cancel(job);
}

final jobsProvider = NotifierProvider<JobsNotifier, List<Job>>(JobsNotifier.new);

/// 実行中のジョブ数（アプリバーのバッジ用）
final runningJobCountProvider = Provider<int>((ref) => ref.watch(jobsProvider).where((j) => j.isRunning).length);
