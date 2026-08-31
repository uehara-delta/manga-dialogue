import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/engine_providers.dart';

/// アプリバー右端の共通ボタン: ジョブ（実行中の件数バッジ付き）と設定
class AppActions extends ConsumerWidget {
  const AppActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(runningJobCountProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'ジョブ',
          icon: Badge(isLabelVisible: running > 0, label: Text('$running'), child: const Icon(Icons.task_alt)),
          onPressed: () => context.push('/jobs'),
        ),
        IconButton(tooltip: '設定', icon: const Icon(Icons.settings_outlined), onPressed: () => context.push('/settings')),
      ],
    );
  }
}
