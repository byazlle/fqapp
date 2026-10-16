import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fqapp/main.dart' as app;

Future<void> pumpFor(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<bool> waitFor(WidgetTester tester, Finder finder, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('novel reader: open and read chapter', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    app.main();
    expect(await waitFor(tester, find.text('今日焦点'), 60), isTrue,
        reason: '首页未加载');

    // 今日焦点的「立即阅读」→ 详情页。
    final readNow = find.text('立即阅读').first;
    expect(readNow, findsOneWidget, reason: '找不到「立即阅读」按钮');
    await tester.ensureVisible(readNow);
    await tester.tap(readNow);
    await tester.pump();

    // 详情页加载目录后，主按钮显示「开始阅读」或「继续阅读」。
    final startBtn = find
        .byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data == '开始阅读' || w.data == '继续阅读'),
        )
        .first;
    expect(await waitFor(tester, startBtn, 60), isTrue,
        reason: '详情页目录未加载出阅读按钮');
    await tester.tap(startBtn);
    await tester.pump();

    // 进入阅读器并等待正文（章节内容来自上游，可能需数秒）。
    expect(await waitFor(tester, find.byKey(const ValueKey('reader-page-surface')), 45),
        isTrue,
        reason: '未进入小说阅读器');
    await pumpFor(tester, 3);
  });
}
