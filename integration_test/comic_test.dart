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

  testWidgets('comic reader: open and decrypt images', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    app.main();
    expect(await waitFor(tester, find.text('今日焦点'), 60), isTrue,
        reason: '首页未加载');

    // 顶部 tab 栏的「漫画」分类（底部导航无此项，唯一）。
    final mangaTab = find.text('漫画').first;
    await tester.tap(mangaTab);
    await tester.pump();

    // 网格里漫画卡片的 key 形如 'manga:xxx'。网格卡片在 spotlight 下方，
    // 测试窗口可能需要先滚动。
    final mangaCard = find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('manga:'),
        )
        .first;
    expect(await waitFor(tester, mangaCard, 60), isTrue,
        reason: '漫画列表未加载');
    await tester.scrollUntilVisible(
      mangaCard,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(mangaCard, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 详情页「开始阅读」。
    final startBtn = find
        .byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data == '开始阅读' || w.data == '继续阅读'),
        )
        .first;
    expect(await waitFor(tester, startBtn, 60), isTrue,
        reason: '漫画详情页未加载阅读按钮');
    await tester.tap(startBtn);
    await tester.pump();

    // 进入漫画阅读器，图片走 Rust loopback 解密。
    final reader = find.byWidgetPredicate(
      (w) =>
          w.key == const ValueKey('comic-reader-pages') ||
          w.key == const ValueKey('comic-reader-paged-view'),
    );
    expect(await waitFor(tester, reader, 45), isTrue,
        reason: '未进入漫画阅读器');
    await pumpFor(tester, 5);
  });
}
