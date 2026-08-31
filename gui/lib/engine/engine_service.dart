/// Python エンジン（manga-dialogue CLI）を子プロセスとして起動し、
/// stdout の JSON Lines をイベントとして配信する。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum JobStatus { running, succeeded, failed, cancelled }

class EngineEvent {
  EngineEvent(this.data) : time = DateTime.now();
  final Map<String, dynamic> data;
  final DateTime time;
  String get type => data['event'] as String? ?? 'unknown';
}

class Job {
  Job({required this.id, required this.label, required this.args, this.run});
  final int id;
  final String label;
  final List<String> args;

  /// ロック対象の run（表示用）
  final String? run;

  final DateTime startedAt = DateTime.now();
  DateTime? endedAt;
  JobStatus status = JobStatus.running;
  int? exitCode;
  Process? process;
  final List<EngineEvent> events = [];
  final StringBuffer stderr = StringBuffer();

  int total = 0;
  int done = 0;
  int failed = 0;
  int inputTokens = 0;
  int outputTokens = 0;
  String? errorMessage;

  final _controller = StreamController<EngineEvent>.broadcast();
  Stream<EngineEvent> get stream => _controller.stream;

  bool get isRunning => status == JobStatus.running;
  double? get progress => total > 0 ? (done + failed) / total : null;
  Duration get elapsed => (endedAt ?? DateTime.now()).difference(startedAt);

  void _onEvent(EngineEvent e) {
    events.add(e);
    switch (e.type) {
      case 'start':
        total = (e.data['total'] as num?)?.toInt() ?? 0;
      case 'page':
        done += 1;
        final u = e.data['usage'] as Map<String, dynamic>?;
        if (u != null) {
          inputTokens += (u['input_tokens'] as num?)?.toInt() ?? 0;
          outputTokens += (u['output_tokens'] as num?)?.toInt() ?? 0;
        }
      case 'page_failed':
        failed += 1;
      case 'error':
        errorMessage = e.data['message'] as String?;
    }
    _controller.add(e);
  }

  void _finish(int code) {
    exitCode = code;
    endedAt = DateTime.now();
    status = switch (code) {
      0 => JobStatus.succeeded,
      130 => JobStatus.cancelled,
      _ => JobStatus.failed,
    };
    if (status == JobStatus.failed && errorMessage == null) {
      final err = stderr.toString().trim();
      errorMessage = err.isEmpty ? '終了コード $code' : err.split('\n').last;
    }
    _controller.close();
  }
}

class EngineConfig {
  const EngineConfig({required this.command, required this.workingDir, required this.worksRoot, this.environment = const {}});

  /// 例: "uv run --env-file .env manga-dialogue" または同梱バイナリのパス
  final String command;
  final String workingDir;
  final String worksRoot;
  final Map<String, String> environment;
}

class EngineService {
  EngineService(this.config);
  EngineConfig config;

  int _nextId = 1;
  final List<Job> jobs = [];
  final _jobsController = StreamController<List<Job>>.broadcast();

  /// ジョブ一覧が変わるたび（開始・イベント・終了）に通知する
  Stream<List<Job>> get changes => _jobsController.stream;

  List<String> _split(String command) => command.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();

  /// コマンドを起動してジョブとして追跡する。args は "--json" と "--root" を除いたコマンド部分
  Future<Job> start(List<String> args, {required String label, String? run}) async {
    final parts = _split(config.command);
    final executable = parts.first;
    final fullArgs = [...parts.skip(1), '--json', ...args, '--root', config.worksRoot];
    final job = Job(id: _nextId++, label: label, args: fullArgs, run: run);
    jobs.insert(0, job);
    _notify();
    try {
      final process = await Process.start(
        executable,
        fullArgs,
        workingDirectory: config.workingDir.isEmpty ? null : config.workingDir,
        environment: config.environment,
        includeParentEnvironment: true,
      );
      job.process = process;
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (!line.startsWith('{')) return;
        try {
          job._onEvent(EngineEvent(jsonDecode(line) as Map<String, dynamic>));
          _notify();
        } catch (_) {}
      });
      process.stderr.transform(utf8.decoder).listen(job.stderr.write);
      unawaited(process.exitCode.then((code) {
        job._finish(code);
        _notify();
      }));
    } catch (e) {
      job.stderr.write('$e');
      job._finish(-1);
      _notify();
    }
    return job;
  }

  /// SIGTERM を送る。エンジンはページ境界で停止して cancelled イベントを出す
  void cancel(Job job) {
    if (job.isRunning) job.process?.kill(ProcessSignal.sigterm);
  }

  /// 一覧系コマンドを実行して全イベントを返す（ジョブ一覧には載せない）。
  /// エラー終了時は error イベントを含む
  Future<List<EngineEvent>> query(List<String> args) async {
    final parts = _split(config.command);
    try {
      final result = await Process.run(
        parts.first,
        [...parts.skip(1), '--json', ...args, '--root', config.worksRoot],
        workingDirectory: config.workingDir.isEmpty ? null : config.workingDir,
        environment: config.environment,
        includeParentEnvironment: true,
      ).timeout(const Duration(minutes: 5));
      final events = <EngineEvent>[];
      for (final line in const LineSplitter().convert(result.stdout as String)) {
        if (!line.startsWith('{')) continue;
        try { events.add(EngineEvent(jsonDecode(line) as Map<String, dynamic>)); } catch (_) {}
      }
      if (result.exitCode != 0 && !events.any((e) => e.type == 'error')) {
        events.add(EngineEvent({'event': 'error', 'message': (result.stderr as String).trim().split('\n').lastOrNull ?? '終了コード ${result.exitCode}'}));
      }
      return events;
    } catch (e) {
      return [EngineEvent({'event': 'error', 'message': '$e'})];
    }
  }

  /// 疎通確認。info イベントを返す（失敗時は null）
  Future<Map<String, dynamic>?> info() async {
    final parts = _split(config.command);
    try {
      final result = await Process.run(
        parts.first,
        [...parts.skip(1), 'info', '--root', config.worksRoot],
        workingDirectory: config.workingDir.isEmpty ? null : config.workingDir,
        environment: config.environment,
        includeParentEnvironment: true,
      ).timeout(const Duration(seconds: 60));
      for (final line in const LineSplitter().convert(result.stdout as String)) {
        if (line.startsWith('{')) return jsonDecode(line) as Map<String, dynamic>;
      }
      return {'event': 'error', 'message': (result.stderr as String).trim()};
    } catch (e) {
      return {'event': 'error', 'message': '$e'};
    }
  }

  void _notify() {
    if (!_jobsController.isClosed) _jobsController.add(List.unmodifiable(jobs));
  }
}
