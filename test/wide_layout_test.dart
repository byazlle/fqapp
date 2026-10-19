// 宽屏（桌面窗口/平板）布局回归：
// - 壳层导航：宽屏回到左侧悬浮导航栏（NavigationRail）、窄屏保持底部药丸
//   （NavigationBar）；配色只跟主题走，**不跟当前 tab 走**。
// - 首页内容列宽随窗口分级（放开列宽让网格扩列，而不是拉伸手机布局）。
// - 设置页 ≥900 改双列（分类列表 + 设置内容），窄屏保持钻取导航。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanqieduanwan/main.dart';
import 'package:fanqieduanwan/pages/drama_page.dart';
import 'package:fanqieduanwan/pages/home_page.dart';
import 'package:fanqieduanwan/pages/home_provider.dart';
import 'package:fanqieduanwan/pages/settings_page.dart';
import 'package:fanqieduanwan/services/api_client.dart';
import 'package:fanqieduanwan/widgets/lazy_indexed_stack.dart';

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

  testWidgets('wide windows bring back the floating left rail', (tester) async {
    await _mountAt(
      tester,
      _scope(
        child: MaterialApp(home: RootShell(backendStarter: () async {})),
      ),
      size: const Size(1280, 800),
    );
    await tester.pumpAndSettle();

    // 宽屏：左侧悬浮导航栏；底部药丸不出现。
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(LazyIndexedStack), findsOneWidget);

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations.length, 4);
    // ≥1200 展开为「图标 + 文字」的扩展形态。
    expect(rail.extended, isTrue);
    // 顶部品牌区：应用名在侧栏里。
    expect(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('首页'),
      ),
      findsOneWidget,
    );

    // 侧栏在窗口左侧，内容在其右侧。
    final railRect = tester.getRect(find.byType(NavigationRail));
    expect(railRect.left, lessThan(120));

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
    // 切页后侧栏还在原位。
    expect(tester.getRect(find.byType(NavigationRail)).left, railRect.left);

    await tester.pump(const Duration(seconds: 25));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('nav keeps one palette on every tab', (tester) async {
    await _mountAt(
      tester,
      _scope(
        child: MaterialApp(home: RootShell(backendStarter: () async {})),
      ),
      size: const Size(1280, 800),
    );
    await tester.pumpAndSettle();

    NavigationRail railOf() =>
        tester.widget<NavigationRail>(find.byType(NavigationRail));
    final before = railOf();
    final indicator = before.indicatorColor;
    final selectedIcon = before.selectedIconTheme?.color;
    final unselectedIcon = before.unselectedIconTheme?.color;

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('短剧'),
      ),
    );
    await tester.pumpAndSettle();

    // 「点短剧颜色就变了」的回归：配色只跟主题走，选中项换了但整条导航的
    // 取色一字未动（v1.2.0 之前这里写的是 `isDark || isDramaTab`）。
    final after = railOf();
    expect(after.selectedIndex, 1);
    expect(after.indicatorColor, indicator);
    expect(after.selectedIconTheme?.color, selectedIcon);
    expect(after.unselectedIconTheme?.color, unselectedIcon);

    await tester.pump(const Duration(seconds: 25));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow windows keep the bottom pill', (tester) async {
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
    // 四标签顺序与既有契约一致。
    final bar = find.byType(NavigationBar);
    final home = tester.getCenter(
      find.descendant(of: bar, matching: find.text('首页')),
    );
    final drama = tester.getCenter(
      find.descendant(of: bar, matching: find.text('短剧')),
    );
    final library = tester.getCenter(
      find.descendant(of: bar, matching: find.text('书架')),
    );
    final mine = tester.getCenter(
      find.descendant(of: bar, matching: find.text('我的')),
    );
    expect(home.dx, lessThan(drama.dx));
    expect(drama.dx, lessThan(library.dx));
    expect(library.dx, lessThan(mine.dx));
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
