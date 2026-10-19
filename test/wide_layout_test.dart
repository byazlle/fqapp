// 宽屏（桌面窗口/平板）布局回归：
// - 壳层导航：所有窗口尺寸共用一条顶部悬浮吸顶导航，配色不随页面变；
// - 内容整体下移一个导航高度，导航压在内容之上。
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
import 'package:fanqieduanwan/widgets/brand/brand_nav_bar.dart';
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

  /// 导航条目里那块选中胶囊的颜色。透明 = 未选中。
  Color? pillColor(WidgetTester tester, String label) {
    final pill = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byKey(Key('nav_item_$label')),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .first;
    return (pill.decoration as BoxDecoration?)?.color;
  }

  testWidgets('every window size uses the same floating top nav', (
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

    // 侧栏与底部药丸都已退役，只剩顶部悬浮导航。
    expect(find.byType(BrandNavBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(LazyIndexedStack), findsOneWidget);

    final nav = tester.widget<BrandNavBar>(find.byType(BrandNavBar));
    expect(nav.destinations.length, 4);
    expect(nav.showBrand, isTrue);
    for (final label in ['首页', '短剧', '书架', '我的']) {
      expect(
        find.descendant(
          of: find.byType(BrandNavBar),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }

    // 吸顶：导航固定在窗口顶部，且压在内容之上。
    final navRect = tester.getRect(find.byType(BrandNavBar));
    expect(navRect.top, lessThan(12));
    // 首页内容从导航下沿开始（壳层把导航高度注入了 MediaQuery.padding.top）。
    expect(
      tester.getRect(find.byKey(const Key('home_feed'))).top,
      greaterThanOrEqualTo(navRect.bottom),
    );

    await tester.tap(find.byKey(const Key('nav_item_短剧')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<LazyIndexedStack>(find.byType(LazyIndexedStack)).index,
      1,
    );
    expect(find.byType(DramaPage), findsOneWidget);

    // 切到黑底视频流后导航位置不变（不随页面滚动/换色而位移）。
    expect(tester.getRect(find.byType(BrandNavBar)).top, navRect.top);
    await tester.pump(const Duration(seconds: 25));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('nav keeps one black/white palette on every tab', (
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

    const selectedInk = Color(0xFF14161B);
    // 首页选中：胶囊是纯黑。
    expect(pillColor(tester, '首页'), selectedInk);
    expect(pillColor(tester, '短剧'), Colors.transparent);

    await tester.tap(find.byKey(const Key('nav_item_短剧')));
    await tester.pumpAndSettle();

    // 切到黑底页面后，选中态依旧是同一块黑胶囊，未选中仍是深色字
    // ——这正是「点短剧颜色就变了」要挡住的回归。
    expect(pillColor(tester, '短剧'), selectedInk);
    expect(pillColor(tester, '首页'), Colors.transparent);
    final homeLabel = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('nav_item_首页')),
        matching: find.text('首页'),
      ),
    );
    expect(homeLabel.style?.color, isNot(Colors.white));

    await tester.pump(const Duration(seconds: 25));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow windows keep the same top nav without the brand block', (
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

    expect(find.byType(BrandNavBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.widget<BrandNavBar>(find.byType(BrandNavBar)).showBrand,
        isFalse);
    // 四标签顺序与既有契约一致。
    final home = tester.getCenter(find.byKey(const Key('nav_item_首页'))).dx;
    final drama = tester.getCenter(find.byKey(const Key('nav_item_短剧'))).dx;
    final library = tester.getCenter(find.byKey(const Key('nav_item_书架'))).dx;
    final mine = tester.getCenter(find.byKey(const Key('nav_item_我的'))).dx;
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
