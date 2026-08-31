import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../engine/engine_service.dart';
import '../../state/engine_providers.dart';

/// エンジン処理の一覧。進捗、経過時間、失敗、ログ、キャンセル。
class JobsScreen extends ConsumerWidget {
  const JobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(jobsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/')),
        title: const Text('ジョブ'),
      ),
      body: jobs.isEmpty
          ? const Center(child: Text('実行したジョブはまだありません'))
          : ListView.builder(
              itemCount: jobs.length,
              itemBuilder: (context, i) => _JobTile(job: jobs[i]),
            ),
    );
  }
}

class _JobTile extends ConsumerWidget {
  const _JobTile({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (job.status) {
      JobStatus.running => (Icons.play_circle_outline, scheme.primary),
      JobStatus.succeeded => (Icons.check_circle_outline, Colors.green),
      JobStatus.failed => (Icons.error_outline, scheme.error),
      JobStatus.cancelled => (Icons.stop_circle_outlined, Colors.grey),
    };
    final tokens = job.inputTokens + job.outputTokens > 0 ? '   入力 ${_fmt(job.inputTokens)} / 出力 ${_fmt(job.outputTokens)} トークン' : '';
    return ExpansionTile(
      leading: Icon(icon, color: color),
      title: Text(job.label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_status(job.status)}   ${job.total > 0 ? '${job.done + job.failed} / ${job.total}' : ''}'
              '${job.failed > 0 ? '   失敗 ${job.failed}' : ''}   ${_elapsed(job.elapsed)}$tokens',
              style: const TextStyle(fontSize: 12)),
          if (job.isRunning && job.progress != null) Padding(padding: const EdgeInsets.only(top: 4), child: LinearProgressIndicator(value: job.progress)),
          if (job.isRunning && job.progress == null) const Padding(padding: EdgeInsets.only(top: 4), child: LinearProgressIndicator()),
          if (job.errorMessage != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(job.errorMessage!, style: TextStyle(color: scheme.error, fontSize: 12))),
        ],
      ),
      trailing: job.isRunning
          ? TextButton(onPressed: () => ref.read(jobsProvider.notifier).cancel(job), child: const Text('キャンセル'))
          : null,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(job.args.join(' '), style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 8),
              Container(
                height: 220,
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
                child: SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    [for (final e in job.events) _describe(e), if (job.stderr.isNotEmpty) '--- stderr ---\n${job.stderr}'].join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _status(JobStatus s) => switch (s) {
        JobStatus.running => '実行中',
        JobStatus.succeeded => '完了',
        JobStatus.failed => '失敗',
        JobStatus.cancelled => '中断',
      };

  static String _elapsed(Duration d) => d.inHours > 0 ? '${d.inHours}h${d.inMinutes % 60}m' : d.inMinutes > 0 ? '${d.inMinutes}m${d.inSeconds % 60}s' : '${d.inSeconds}s';
  static String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  static String _describe(EngineEvent e) {
    final d = e.data;
    final t = '${e.time.hour.toString().padLeft(2, '0')}:${e.time.minute.toString().padLeft(2, '0')}:${e.time.second.toString().padLeft(2, '0')}';
    return switch (e.type) {
      'page' => '$t  page ${(d['page'] as num?)?.toString().padLeft(4, '0')}  ${d['lines']} lines'
          '${(d['new_characters'] as List?)?.isNotEmpty == true ? '  新キャラ: ${(d['new_characters'] as List).join(', ')}' : ''}',
      'page_failed' => '$t  失敗 page ${d['page']}: ${d['message']}',
      'proposal' => '$t  [${d['status']} ${d['confidence']}] ${d['from_name']} → ${d['to_name']}',
      'change' => '$t  v${d['volume']} p${d['page']} #${d['index']}: ${d['reason']}',
      'error' => '$t  エラー: ${d['message']}',
      _ => '$t  ${e.type}  ${d.entries.where((x) => x.key != 'event').map((x) => '${x.key}=${x.value}').join(' ')}',
    };
  }
}
