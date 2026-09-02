import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/capture/captures_screen.dart';
import 'features/home/home_screen.dart';
import 'features/jobs/jobs_screen.dart';
import 'features/page_editor/page_editor_screen.dart';
import 'features/review/review_screen.dart';
import 'features/settings/settings_screen.dart';
import 'state/providers.dart';

/// 開発用: MD_INITIAL_ROUTE で起動時の画面を指定できる
final router = GoRouter(
  initialLocation: Platform.environment['MD_INITIAL_ROUTE'] ?? '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(path: '/jobs', builder: (context, state) => const JobsScreen()),
    GoRoute(
      path: '/captures/:title/:volume',
      builder: (context, state) => CapturesScreen(title: state.pathParameters['title']!, volume: int.parse(state.pathParameters['volume']!)),
    ),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(
      path: '/review/:title/:run',
      builder: (context, state) => ReviewScreen(title: state.pathParameters['title']!, run: state.pathParameters['run']!),
    ),
    GoRoute(
      path: '/edit/:title/:run/:volume',
      builder: (context, state) => PageEditorScreen(
        title: state.pathParameters['title']!,
        run: state.pathParameters['run']!,
        volume: int.parse(state.pathParameters['volume']!),
        page: int.tryParse(state.uri.queryParameters['page'] ?? ''),
      ),
    ),
  ],
);

class MangaDialogueApp extends ConsumerWidget {
  const MangaDialogueApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(settingsProvider.select((s) => s.uiScale));
    return MaterialApp.router(
        title: 'manga-dialogue',
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        theme: ThemeData(colorSchemeSeed: const Color(0xFF2B4C8C), useMaterial3: true, visualDensity: VisualDensity.compact),
        darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF2B4C8C), brightness: Brightness.dark, useMaterial3: true, visualDensity: VisualDensity.compact),
        routerConfig: router,
      );
  }
}
