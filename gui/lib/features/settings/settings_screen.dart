import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../engine/engine_locator.dart';
import '../../state/engine_providers.dart';
import '../../state/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final _command = TextEditingController(text: ref.read(settingsProvider).engineCommand);
  late final _workingDir = TextEditingController(text: ref.read(settingsProvider).engineWorkingDir ?? '');
  late final _anthropicKey = TextEditingController(text: ref.read(settingsProvider).apiKeys['ANTHROPIC_API_KEY'] ?? '');
  late final _geminiKey = TextEditingController(text: ref.read(settingsProvider).apiKeys['GEMINI_API_KEY'] ?? '');
  Map<String, dynamic>? _info;
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/')),
        title: const Text('設定'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('表示', style: Theme.of(context).textTheme.titleMedium),
          Row(
            children: [
              const Text('文字の大きさ'),
              Expanded(
                child: Slider(
                  value: settings.uiScale,
                  min: 0.8,
                  max: 1.8,
                  divisions: 10,
                  label: '${(settings.uiScale * 100).round()}%',
                  onChanged: (v) => ref.read(settingsProvider.notifier).update((s) => s.uiScale = (v * 10).round() / 10),
                ),
              ),
              SizedBox(width: 48, child: Text('${(settings.uiScale * 100).round()}%', textAlign: TextAlign.end)),
            ],
          ),
          const SizedBox(height: 24),
          Text('作品データ', style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(settings.worksRoot, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            subtitle: const Text('works フォルダ。エンジンには --root として渡されます'),
            trailing: TextButton(
              child: const Text('変更'),
              onPressed: () async {
                final dir = await FilePicker.getDirectoryPath(dialogTitle: 'works フォルダを選択');
                if (dir != null) {
                  ref.read(settingsProvider.notifier).update((s) => s.worksRoot = dir);
                  ref.read(worksProvider.notifier).refresh();
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          Text('エンジン', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _command,
            decoration: const InputDecoration(labelText: '起動コマンド', helperText: '開発時: uv run --env-file .env manga-dialogue   配布時: 同梱バイナリのパス'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _workingDir,
            decoration: InputDecoration(
              labelText: '作業ディレクトリ',
              helperText: 'uv run の場合はリポジトリのパス（空欄なら pyproject.toml のあるリポジトリを自動検出）',
              suffixIcon: IconButton(
                icon: const Icon(Icons.folder_open),
                onPressed: () async {
                  final dir = await FilePicker.getDirectoryPath(dialogTitle: 'エンジンの作業ディレクトリ');
                  if (dir != null) setState(() => _workingDir.text = dir);
                },
              ),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          const SizedBox(height: 24),
          Text('API キー', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('エンジンに環境変数として渡します。空欄なら .env や環境変数の値が使われます。この設定ファイル（~/.manga_dialogue_gui.json）に平文で保存されます。', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(controller: _geminiKey, obscureText: true, decoration: const InputDecoration(labelText: 'GEMINI_API_KEY')),
          const SizedBox(height: 8),
          TextField(controller: _anthropicKey, obscureText: true, decoration: const InputDecoration(labelText: 'ANTHROPIC_API_KEY')),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton(
                onPressed: () {
                  ref.read(settingsProvider.notifier).update((s) {
                    s.engineCommand = _command.text.trim();
                    s.engineWorkingDir = _workingDir.text.trim().isEmpty ? null : _workingDir.text.trim();
                    s.apiKeys = {'GEMINI_API_KEY': _geminiKey.text.trim(), 'ANTHROPIC_API_KEY': _anthropicKey.text.trim()};
                  });
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存しました')));
                },
                child: const Text('保存'),
              ),
              const SizedBox(width: 12),
              if (EngineLocator.bundledPath() != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('同梱エンジンを使う'),
                  onPressed: () => setState(() { _command.text = EngineLocator.bundledPath()!; _workingDir.text = ''; }),
                ),
              if (EngineLocator.bundledPath() != null) const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: _checking ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link),
                label: const Text('接続確認'),
                onPressed: _checking
                    ? null
                    : () async {
                        setState(() => _checking = true);
                        final info = await ref.read(engineServiceProvider).info();
                        setState(() { _info = info; _checking = false; });
                      },
              ),
            ],
          ),
          if (_info != null) ...[
            const SizedBox(height: 16),
            _InfoCard(info: _info!),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.info});
  final Map<String, dynamic> info;
  @override
  Widget build(BuildContext context) {
    if (info['event'] == 'error') {
      return Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text('接続できません: ${info['message']}')));
    }
    final providers = info['providers'] as Map<String, dynamic>? ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('エンジン ${info['version']}  (Python ${info['python']}, ${info['platform']})'),
            Text('既定モデル: ${info['default_model']}'),
            for (final e in providers.entries)
              Text('${e.key}: API キー ${(e.value as Map)['api_key'] == true ? '設定済み' : '未設定'}'),
            Text('works: ${info['root']}${info['root_exists'] == true ? '' : '（存在しません）'}'),
          ],
        ),
      ),
    );
  }
}
