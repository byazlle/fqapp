import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fqapp/models/media_item.dart';
import 'package:fqapp/services/player_preferences.dart';
import 'package:fqapp/widgets/video_player_chrome.dart';

import 'support/controlled_player.dart';

/// 桌面端键盘快捷键与对应可点击控件。
///
/// 快捷键约定（`video_player_chrome._handlePlayerKey`）：
/// - 空格：播放/暂停（可点击控件：运输条/横屏条播放钮）
/// - ↑/↓：快进/快退 10 秒，长按连续步进（可点击控件：±10 秒钮）
/// - ←/→：音量 ±5%，长按连续步进（可点击控件：静音钮 + 滑杆）
/// - S：倍速循环切换并记忆（可点击控件：倍速面板/横屏倍速文字钮）
///
/// 注意：flutter test 跑在 Windows 上，`Platform.isWindows` 为真，
/// 桌面门控在这里天然打开。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'player_playback_rate': 1});
  });

  testWidgets('up and down arrows seek ten seconds, long press steps', (
    tester,
  ) async {
    final player = ControlledNativePlayer()..playbackRequested = true;
    await player.create('https://example.invalid/a.mp4', '');
    await _mount(tester, player);

    // 单次 ↑：从 0 秒快进 10 秒。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(player.calls, contains('seek:10000ms'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    // 单次 ↓：从 10 秒快退 10 秒，钳回 0。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(player.calls, contains('seek:0ms'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    // 长按 ↑：立即一次 + 150ms 连续步进（0 → 10 → 20 → …）。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    final seeks = player.calls
        .where((call) => call.startsWith('seek:'))
        .toList();
    expect(seeks.length, greaterThanOrEqualTo(4));
    expect(seeks.last, 'seek:40000ms');
    // 松键后停步。
    final settled = player.calls.length;
    await tester.pump(const Duration(milliseconds: 400));
    expect(player.calls.length, settled);
  });

  testWidgets('space toggles playback', (tester) async {
    final player = ControlledNativePlayer()..playbackRequested = true;
    await player.create('https://example.invalid/a.mp4', '');
    await _mount(tester, player);

    final handled = await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(handled, isTrue);
    await tester.pump();
    expect(player.calls, contains('pause'));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(player.calls, contains('play'));
  });

  testWidgets('S cycles playback rate and persists the choice', (tester) async {
    final player = ControlledNativePlayer()..playbackRequested = true;
    await player.create('https://example.invalid/a.mp4', '');
    await _mount(tester, player);

    // 初始档位 1（setUp 的 mock 值）。
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    expect(player.calls, contains('rate:1.25'));
    expect(await PlayerPreferences.loadPlaybackRate(), 1.25);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    expect(player.calls, contains('rate:1.5'));
    expect(await PlayerPreferences.loadPlaybackRate(), 1.5);
  });

  testWidgets('arrow keys adjust volume; mute button and slider are clickable', (
    tester,
  ) async {
    final player = ControlledNativePlayer()..playbackRequested = true;
    await player.create('https://example.invalid/a.mp4', '');
    // 默认静音策略：起播音量 0。
    await _mount(tester, player, defaultMute: true);

    // 宽屏（900px ≥ 600）：音量组带滑杆。
    expect(find.byKey(const ValueKey('player-volume')), findsOneWidget);

    // ←/→ 步进 5%。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(player.calls, contains('volume:0.05'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(player.calls, contains('volume:0.1'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(player.calls, contains('volume:0.05'));

    // 静音钮（可点击控件）：0.05 → 静音 → 恢复。
    await tester.tap(find.byTooltip('静音'));
    await tester.pump();
    expect(player.calls, contains('volume:0.0'));
    expect(find.byTooltip('取消静音'), findsOneWidget);
    await tester.tap(find.byTooltip('取消静音'));
    await tester.pump();
    expect(player.calls, contains('volume:0.05'));

    // 滑杆（可点击控件）：点轨道中点 ≈ 0.5。
    final slider = find.byKey(const ValueKey('player-volume'));
    await tester.tapAt(tester.getCenter(slider));
    await tester.pump();
    final volumes = player.calls
        .where((call) => call.startsWith('volume:'))
        .map((call) => double.parse(call.substring('volume:'.length)))
        .toList();
    expect(volumes.last, closeTo(0.5, 0.05));

    // 长按 ←：从 0.5 连续降到 0（10 步 × 5%），并翻成取消静音态。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(player.calls.last, 'volume:0.0');
    expect(find.byTooltip('取消静音'), findsOneWidget);
  });

  testWidgets('volume keeps the default mute switch in sync', (tester) async {
    final player = ControlledNativePlayer()..playbackRequested = true;
    await player.create('https://example.invalid/a.mp4', '');
    final muteSwitches = <bool>[];
    await _mount(
      tester,
      player,
      shortSeries: true,
      defaultMute: true,
      onDefaultMuteChanged: muteSwitches.add,
    );

    // 从 0 调上去 → 同步关闭「默认静音」开关。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(player.calls, contains('volume:0.05'));
    expect(muteSwitches, [false]);

    // 调回 0 → 同步打开开关（下一集起播沿用静音策略）。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(player.calls, contains('volume:0.0'));
    expect(muteSwitches, [false, true]);
  });

  testWidgets('volume policy resets when the episode player changes', (
    tester,
  ) async {
    final player = ControlledNativePlayer()..playbackRequested = true;
    await player.create('https://example.invalid/a.mp4', '');
    final second = ControlledNativePlayer()..playbackRequested = true;
    await second.create('https://example.invalid/b.mp4', '');
    addTearDown(second.dispose);
    await _mount(tester, player, defaultMute: true);

    // 手调音量离开 0。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.byTooltip('静音'), findsOneWidget);

    // 换播放器（下一集）：回到起播策略音量（官方语义：每次新建播放器
    // 都重新套一遍「默认静音」）。
    await tester.pumpWidget(_app(second, defaultMute: true));
    await tester.pump();
    expect(find.byTooltip('取消静音'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape bar exposes seek, volume and keyboard shortcuts', (
    tester,
  ) async {
    final player = ControlledNativePlayer()..playbackRequested = true;
    await player.create('https://example.invalid/a.mp4', '');
    await _mount(tester, player, shortSeries: true, landscape: true);

    // 横屏底条的 ±10 秒钮（键盘 ↑/↓ 的可点击控件）。
    await tester.tap(find.byKey(const ValueKey('landscape-forward-10')));
    await tester.pump();
    expect(player.calls, contains('seek:10000ms'));
    await tester.tap(find.byKey(const ValueKey('landscape-replay-10')));
    await tester.pump();
    expect(player.calls, contains('seek:0ms'));

    // 横屏底条的音量钮（键盘 ←/→ 与静音的可点击控件）。
    expect(find.byKey(const ValueKey('landscape-volume')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-volume')), findsOneWidget);
    await tester.tap(find.byTooltip('静音'));
    await tester.pump();
    expect(player.calls, contains('volume:0.0'));

    // 横屏下快捷键照旧工作。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(player.calls, contains('seek:10000ms'));
  });

  testWidgets('portrait catalog bar carries the desktop control cluster', (
    tester,
  ) async {
    final player = ControlledNativePlayer()..playbackRequested = true;
    await player.create('https://example.invalid/a.mp4', '');
    await _mount(tester, player, shortSeries: true);

    // 目录条右侧的桌面专属控件：音量组 + ±10 秒（快捷键的可点击控件）。
    await tester.tap(find.byTooltip('静音'));
    await tester.pump();
    expect(player.calls, contains('volume:0.0'));
    await tester.tap(find.byTooltip('取消静音'));
    await tester.pump();
    expect(player.calls, contains('volume:1.0'));
    await tester.tap(find.byTooltip('快进10秒'));
    await tester.pump();
    expect(player.calls, contains('seek:10000ms'));
    await tester.tap(find.byTooltip('快退10秒'));
    await tester.pump();
    expect(player.calls, contains('seek:0ms'));
  });

  testWidgets('narrow portrait window keeps the official catalog bar', (
    tester,
  ) async {
    final player = ControlledNativePlayer()..playbackRequested = true;
    await player.create('https://example.invalid/a.mp4', '');
    await _mount(
      tester,
      player,
      shortSeries: true,
      window: const Size(500, 900),
    );

    // 窄窗（<560）不放桌面控制簇，目录条保持官方形态；快捷键仍可用。
    expect(find.byTooltip('快退10秒'), findsNothing);
    expect(find.byTooltip('静音'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(player.calls, contains('seek:10000ms'));
  });

  testWidgets('narrow desktop window drops the volume slider only', (
    tester,
  ) async {
    final player = ControlledNativePlayer()..playbackRequested = true;
    await player.create('https://example.invalid/a.mp4', '');
    await _mount(tester, player, window: const Size(500, 900));

    // 窄窗不放滑杆，静音钮仍在（键鼠仍可静音/取消静音）。
    expect(find.byKey(const ValueKey('player-volume')), findsNothing);
    expect(find.byTooltip('静音'), findsOneWidget);
    await tester.tap(find.byTooltip('静音'));
    await tester.pump();
    expect(player.calls, contains('volume:0.0'));
  });
}

Future<void> _mount(
  WidgetTester tester,
  ControlledNativePlayer player, {
  bool shortSeries = false,
  bool landscape = false,
  bool defaultMute = false,
  ValueChanged<bool>? onDefaultMuteChanged,
  Size window = const Size(900, 600),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = landscape ? const Size(900, 420) : window;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Double-tap recognizers leave a short minimum-tap timer after a drag.
    await tester.pump(const Duration(milliseconds: 350));
    await player.dispose();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  await tester.pumpWidget(
    _app(
      player,
      shortSeries: shortSeries,
      defaultMute: defaultMute,
      onDefaultMuteChanged: onDefaultMuteChanged,
    ),
  );
  await tester.pumpAndSettle();
  if (landscape) {
    // 短剧横屏入口是信息区的「全屏观看」胶囊（`player-fullscreen-pill`）。
    await tester.tap(find.byKey(const ValueKey('player-fullscreen-pill')));
    await tester.pumpAndSettle();
  }
}

Widget _app(
  ControlledNativePlayer player, {
  bool shortSeries = false,
  bool defaultMute = false,
  ValueChanged<bool>? onDefaultMuteChanged,
}) {
  // 宿主等价物：`onDefaultMuteChanged` 翻转后重建 chrome（真实宿主是
  // player_page 的 `_setDefaultMute` → setState），否则 chrome 看到的
  // `defaultMute` 永远是旧值，同步判断会失灵。
  final mute = ValueNotifier<bool>(defaultMute);
  return MaterialApp(
    home: StreamBuilder<bool>(
      stream: player.playingStream,
      initialData: player.playing,
      builder: (context, playing) => ValueListenableBuilder<bool>(
        valueListenable: mute,
        builder: (context, muted, _) => VideoPlayerChrome(
          player: player,
          title: '快捷键测试',
          episodes: List.generate(
            3,
            (i) => Chapter(itemId: '$i', title: '第 ${i + 1} 集', volumeName: ''),
          ),
          currentIndex: 0,
          duration: player.duration,
          playing: playing.data!,
          shortSeries: shortSeries,
          defaultMute: muted,
          onDefaultMuteChanged: onDefaultMuteChanged == null
              ? null
              : (value) {
                  mute.value = value;
                  onDefaultMuteChanged(value);
                },
          onSelectEpisode: (value) async {},
          onError: (error) => throw error,
          child: const ColoredBox(color: Colors.black),
        ),
      ),
    ),
  );
}
