// 宽屏（桌面窗口/平板）布局回归：
// - 壳层导航：≥900 用左侧悬浮导航栏替代底部药丸，四个 tab 不变；
//   窄屏保持底部药丸（手机形态逐像素不变的守卫）。
// - 首页内容列宽随窗口分级（放开列宽让网格扩列，而不是拉伸手机布局）。
// - 设置页 ≥900 改双列（分类列表 + 设置内容），窄屏保持钻取导航。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liuguang/main.dart';
import 'package:liuguang/pages/drama_page.dart';
import 'package:liuguang/pages/home_page.dart';
import 'package:liuguang/pages/home_provider.dart';
import 'package:liuguang/pages/settings_page.dart';
import 'package:liuguang/services/api_client.dart';
import 'package:liuguang/widgets/lazy_indexed_stack.dart';

/// 空回包的 notifier：不触网、不起定时器，pumpAndSettle 不会挂起。
HomeNotifier _emptyNotifier({int initialTabIndex = 0}) => HomeNotifier(
  initialTabIndex: initialTabIndex,
  homepageLoader:
      ({int tabType = 2, int offset = 0, String? sessionId}) async =>
          const HomepagePage(items: [], nextOffset: null, sessionId: null),
  searchLoader: (query, {int page = 1}) async => const [],
);

ProviderScope _scope({required Widget child, int dramaTabIndex = 0}) =>
    ProviderScope(
      overrides: [
        homeProvider.overrideWith(() => _emptyNotifier()),
        dramaProvider.overrideWith(
          () => _emptyNotifier(initialTabIndex: dramaTabIndex),
        ),
      ],
      child: child,
    );

/// 按窗口尺寸挂载，dpr=1，测试结束还原。
Future<void> _mountAt(
  WidgetTester tester,
  Widget child, {
  required Size size,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() => tester.view.reset());
  await tester.pumpWidget(child);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('wide shell swaps the bottom pill for a left navigation rail', (
    tester,
  ) async {
    await _mountAt(
      tester,
      _scope(
        child: MaterialApp(home: RootShell(backendStarter: () async {})),
      ),
      size: const Size(1280, 800),
    );
    await tester.pumpAndSettle();

    // 宽屏：左侧导航栏在、底部药丸不在。
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(LazyIndexedStack), findsOneWidget);

    // 四个一级目的地与手机端同源：同一批标签。
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations.length, 4);
    for (final label in ['首页', '短剧', '书架', '我的']) {
      expect(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }

    // 点侧栏切 tab：LazyIndexedStack 的 index 跟着走（短剧页按既有 shell
    // 测试同款 drain 真实目录请求的定时器）。
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('短剧'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<LazyIndexedStack>(find.byType(LazyIndexedStack)).index,
      1,
    );
    expect(find.byType(DramaPage), findsOneWidget);
    await tester.pump(const Duration(seconds: 25));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('extra-wide shell extends the rail with labels beside icons', (
    tester,
  ) async {
    await _mountAt(
      tester,
      _scope(
        child: MaterialApp(home: RootShell(backendStarter: () async {})),
      ),
      size: const Size(1400, 900),
    );
    await tester.pumpAndSettle();

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
    // 扩展态：标签排在图标右侧（dx 更大）；非扩展态才在图标下方。
    // （rail 内部把 destination 转成私有的 _RailDestination，只能按
    // rail 作用域内的文本/图标定位。）
    final railFinder = find.byType(NavigationRail);
    final iconCenter = tester.getCenter(
      find.descendant(of: railFinder, matching: find.byType(Icon).first),
    );
    final labelCenter = tester.getCenter(
      find.descendant(of: railFinder, matching: find.text('首页')),
    );
    expect(labelCenter.dx, greaterThan(iconCenter.dx));
  });

  testWidgets('narrow shell keeps the bottom pill (mobile layout untouched)', (
    tester,
  ) async {
    await _mountAt(
      tester,
      _scope(
        child: MaterialApp(home: RootShell(backendStarter: () async {})),
      ),
      size: const Size(400, 800),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    // 药丸四标签的顺序与既有契约一致。
    Finder navLabel(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );
    final home = tester.getCenter(navLabel('首页')).dx;
    final drama = tester.getCenter(navLabel('短剧')).dx;
    final library = tester.getCenter(navLabel('书架')).dx;
    final mine = tester.getCenter(navLabel('我的')).dx;
    expect(home, lessThan(drama));
    expect(drama, lessThan(library));
    expect(library, lessThan(mine));
    expect(tester.takeException(), isNull);
  });

  testWidgets('home feed content width widens in steps on wide windows', (
    tester,
  ) async {
    Future<double> feedWidth(Size size) async {
      await _mountAt(
        tester,
        _scope(child: const MaterialApp(home: HomePage())),
        size: size,
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byKey(const Key('home_feed'))).width;
    }

    // 窄窗：仍是既有的 840 列宽上限（窗口更窄时被窗口截断）。
    expect(await feedWidth(const Size(800, 900)), closeTo(800, 1));
    // 900~1280：放开到 920，让网格扩列而不是拉伸卡片。
    expect(await feedWidth(const Size(1000, 900)), closeTo(920, 1));
    // ≥1280：1080。
    expect(await feedWidth(const Size(1280, 900)), closeTo(1080, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide settings uses a two-column layout without pushing', (
    tester,
  ) async {
    await _mountAt(
      tester,
      const MaterialApp(home: SettingsPage()),
      size: const Size(1280, 860),
    );
    await tester.pumpAndSettle();

    // 右列默认显示第一个分类（外观）的内容。
    expect(find.text('深色模式'), findsOneWidget);
    // 双列不需要 push：点左列分类，右列内容原地切换。
    await tester.tap(find.text('听书'));
    await tester.pumpAndSettle();
    expect(find.text('系统朗读'), findsOneWidget);
    expect(find.text('深色模式'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow settings keeps the drill-in list', (tester) async {
    await _mountAt(
      tester,
      const MaterialApp(home: SettingsPage()),
      size: const Size(400, 860),
    );
    await tester.pumpAndSettle();

    // 窄屏：分类列表在，子页内容不预建。
    expect(find.text('听书'), findsOneWidget);
    expect(find.text('系统朗读'), findsNothing);
    await tester.tap(find.text('听书'));
    await tester.pumpAndSettle();
    expect(find.text('系统朗读'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
