import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'services/desktop_media_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'dart:async';
import 'dart:io' show Platform, File;
import 'dart:ui' show ImageFilter;

import 'pages/home_page.dart';
import 'pages/audio_page.dart';
import 'pages/cached_books_page.dart';
import 'pages/drama_page.dart';
import 'pages/library_page.dart';
import 'pages/mine_page.dart';
import 'services/app_log.dart';
import 'services/app_theme.dart';
import 'services/audio_preferences.dart';
import 'services/backend_service.dart';
import 'services/digg_store.dart';
import 'services/drama_download_store.dart';
import 'services/drama_downloader.dart';
import 'services/connectivity_status.dart';
import 'services/home_feed_cache.dart';
import 'services/library_store.dart';
import 'services/native_player.dart';
import 'services/rank_cache.dart';
import 'services/player_style_config.dart';
import 'services/short_series_font_scale.dart';
import 'services/playlet_share.dart';
import 'services/poster_cache.dart';
import 'services/shelf_store.dart';
import 'services/swipe_guide_store.dart';
import 'widgets/lazy_indexed_stack.dart';
import 'widgets/home/home_design.dart';

void main() {
  // ensureInitialized 与 runApp 必须在同一个 zone：否则 BindingBase
  // debugCheckZone 会报 Zone mismatch（桌面 debug 下会打断启动）。因此把
  // 全部启动逻辑都放进 runZonedGuarded 内部，而非先在根 zone 初始化 binding。
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      // 桌面端短剧/听书播放走 media_kit（libmpv），必须在创建播放器前初始化。
      // Android 用原生 ExoPlayer，无需初始化。
      // libmpv 缺失（打包漏件、PATH 没带上）时不能拖垮整个启动：与本地数据
      // 开箱失败同一纪律——记一条错误日志让排障有据，应用照常起，桌面播放
      // 按单次播放报错（DesktopMediaPlayer.create 的兜底初始化会再试一次
      // 并把失败转成播放器错误流），其余功能不受影响。
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        try {
          MediaKit.ensureInitialized();
          // 初始化成功才放行桌面播放；失败时保持未就绪，播放器会直接提示
          // 「播放组件缺失」而非含糊地等待加载超时。
          markLibMpvReady();
        } catch (error, stack) {
          AppLog.e(
            'media_kit',
            'media_kit 初始化失败（缺少 libmpv？），桌面视频/听书播放不可用',
            error: error,
            stack: stack,
          );
        }
      }
      // 应用内日志：接管 debugPrint 与 FlutterError.onError，未处理异步异常由
      // runZonedGuarded 捕获；文件持久化异步开启，失败只退回内存模式。
      AppLog.instance.install();
      unawaited(AppLog.instance.startPersistence());
      // 短剧分享的「系统分享」走 Android 的 Intent.ACTION_SEND
      //（官方同一条路径）。桥不可用时 PlayletShare 自动降级为复制链接，
      // 不会把失败说成成功。
      // 插件回 false 表示没能调起选择器（没有可分享的应用），必须原样返回：
      // 「调不起来」与「已分享」是两件事。
      SharePlusLite.handler = ({required title, required text}) async {
        final launched = await const MethodChannel(
          'fqapp/share',
        ).invokeMethod<bool>('shareText', {'title': title, 'text': text});
        return launched ?? false;
      };
      // Rust 核心日志的读取入口：日志页「Rust」视图读 runtime_dir/rust.log。
      // 核心只在 Android 落盘（桌面/测试构建不装 logger），读不到时页面给空态。
      RustLogSource.reader = BackendService.instance.readRustLog;
      runApp(const ProviderScope(child: FqApp()));
    },
    (error, stack) =>
        AppLog.e('zone', '未捕获异步异常', error: error, stack: stack),
  );
}

Future<void> _initializeLocalData() async {
  // 允许在设置中把缓存/数据目录迁移到自定义位置：读出覆盖值后用 Hive.init
  // 指向新目录；否则走默认的 Hive.initFlutter()（应用支持目录）。
  final sp0 = await SharedPreferences.getInstance();
  final cacheOverride = sp0.getString('cacheDirOverride');
  if (cacheOverride != null && cacheOverride.isNotEmpty) {
    Hive.init(cacheOverride);
    // 图片缓存也跟随迁移目录，和 Hive 数据同处一地。必须在 PosterCache
    // 单例首次被访问（下方 enforceBudget）之前赋值，否则仍会落到临时目录。
    PosterCache.overrideBaseDir = cacheOverride;
  } else {
    await Hive.initFlutter();
  }
  // 保证同一时间只有一个播放实例在播放：任一播放器开始播放时，其余自动暂停。
  NativePlayer.beforePlay = (active) => NativePlayer.pauseOthers(active);
  await LibraryStore.instance.init();
  // The 加入书架 collection is optional data: a failure here must not block
  // startup, which is why it shares the retryable bootstrap with the history.
  await ShelfStore.instance.init();
  // 短剧 feed 的 点赞 也是可选本地数据，与书架同一处理：开箱失败不能让
  // 启动失败，否则一个纯装饰性的集合会拖住短剧页之外的所有功能。
  try {
    await DiggStore.instance.init();
  } catch (_) {
    // DiggStore 自己把「不可用」当成「没有点赞」处理（见 _openBox）。
  }
  // 「上滑查看更多视频」的一次性标记同样是可选数据：读不到就当没弹过，
  // 弹一次的语义退化成「本次启动弹一次」也不能拖住启动。
  try {
    await SwipeGuideStore.instance.init();
  } catch (_) {
    // SwipeGuideStore 自己把「不可用」当成「未显示」处理。
  }
  // 首页 feed 的冷启动缓存也是可选数据：打不开就当没有缓存，
  // 首页退化为先加载再显示，其余行为不变。
  try {
    HomeFeedCache.hiveReady = true;
    await HomeFeedCache.instance.warmUp();
  } catch (_) {
    // HomeFeedCache 自己把「不可用」当成「没有缓存」处理。
  }
  // 榜单缓存同理：开箱失败只是退化为每次现拉。
  try {
    RankCache.hiveReady = true;
    await RankCache.instance.warmUp();
  } catch (_) {
    // RankCache 自己把「不可用」当成「没有缓存」处理。
  }
  // 官方播放页开关（PlayerBottomStyleConfig / 清屏反转 / 横屏锁）随同一份
  // 运行时配置读取；读不到就用默认值，不能拖住启动。
  await PlayerStyleConfig.load();
  // 官方播放页字号档（jk3/b 的 SP）同理：读失败回标准档，不拖启动。
  await ShortSeriesFontScale.load();
  // 听书后台播放开关：异步读取 SharedPreferences，失败退化为默认开启。
  unawaited(AudioPreferences.instance.load());
  // 离线缓存的记录箱启动即打开：播放器的离线命中只在 box 就绪时才查
  // （避免运行中途首次 openBox 失败产生游离异步错误）。可选数据，失败
  // 只退化为「本会话不查离线」。
  try {
    await HiveDramaDownloadStore.instance.warmUp();
  } catch (_) {}
  // 离线缓存的网络门（官方 onNetChangeCheck）：断网/只剩计费链路时
  // 自动暂停下载队列，半成品保留。监听失败只退化为「无自动暂停」。
  // Linux 桌面的 connectivity 插件依赖 NetworkManager + system dbus；环境缺
  // 这些时订阅会游离出连接错误（真实 Windows 走系统网络 API，不受影响）。
  // 因此在 Linux 上先探测 system dbus，缺失就跳过，降级为「不自动暂停下载」。
  var canListenConnectivity = true;
  if (Platform.isLinux) {
    canListenConnectivity =
        File('/var/run/dbus/system_bus_socket').existsSync();
  }
  if (canListenConnectivity) {
    try {
      Connectivity().onConnectivityChanged.listen(
        (results) {
          final view = foldConnectivity(results);
          DramaDownloader.instance.updateConnectivity(
            online: view.online,
            metered: view.metered,
          );
        },
        onError: (Object _) {},
      );
    } catch (_) {}
  }
  // 海报缓存的字节预算清扫：超额时删最旧的图。失败不影响任何页面。
  unawaited(PosterCache.instance.enforceBudget());
  final sp = await SharedPreferences.getInstance();
  // Note: Optional preference schemas cannot block local data startup; see
  // .agents/notes/implemented/bug-fix/2026-09-17-persistent-data-and-web-cancellation.md.
  final savedTheme = sp.get(themeModeKey);
  themeModeNotifier.value = themeModeFromName(
    savedTheme is String ? savedTheme : null,
  );
  // 墨水屏模式与深色模式同为可选偏好：读不到退化为关闭，不拖住启动。
  einkModeNotifier.value = sp.getBool(einkModeKey) ?? false;
}

class FqApp extends StatefulWidget {
  const FqApp({super.key});

  @override
  State<FqApp> createState() => _FqAppState();
}

class _FqAppState extends State<FqApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: einkModeNotifier,
          builder: (context, eink, _) {
            // 墨水屏强制浅色纯黑白：深色反白在墨水屏上残影最重。
            final effectiveMode = eink ? ThemeMode.light : mode;
            return MaterialApp(
              navigatorKey: _navigatorKey,
              builder: (context, child) => AudioPlaybackScope(
                navigatorKey: _navigatorKey,
                child: child ?? const SizedBox.shrink(),
              ),
              title: 'fqapp',
              debugShowCheckedModeBanner: false,
              theme: _theme(Brightness.light, eink: eink),
              darkTheme: _theme(Brightness.dark, eink: eink),
              themeMode: effectiveMode,
              home: const AppBootstrap(child: RootShell()),
            );
          },
        );
      },
    );
  }

  ThemeData _theme(Brightness brightness, {bool eink = false}) =>
      AppTheme.createTheme(brightness, einkMode: eink);
}

/// Opens local data before any page can access LibraryStore's boxes. Failed
/// initialization is retryable without clearing or replacing the user's data.
/// See .agents/notes/implemented/bug-fix/2026-09-17-reviewed-runtime-boundaries.md.
class AppBootstrap extends StatefulWidget {
  final Widget child;
  final Future<void> Function()? initializer;

  const AppBootstrap({super.key, required this.child, this.initializer});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool _initializing = false;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (_initializing || _ready) return;
    setState(() {
      _initializing = true;
      _failed = false;
    });
    try {
      await (widget.initializer ?? _initializeLocalData)();
      if (mounted) setState(() => _ready = true);
    } catch (e, st) {
      AppLog.e('bootstrap', '本地数据初始化失败', error: e, stack: st);
      if (mounted) setState(() => _failed = true);
    } finally {
      _initializing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_failed)
                  Icon(
                    LucideIcons.triangle_alert,
                    color: Theme.of(context).colorScheme.error,
                  )
                else
                  const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(_failed ? '无法读取本地数据' : '正在读取本地数据…'),
                if (_failed) ...[
                  const SizedBox(height: 8),
                  const Text('请检查设备可用空间后重试。', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _initialize,
                    child: const Text('重试'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  final Future<void> Function()? backendStarter;

  const RootShell({super.key, this.backendStarter});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  bool _backendReady = false;
  String? _backendError;

  /// 四个一级目的地。底部药丸（窄屏/手机）与左侧导航栏（宽屏/桌面）
  /// 共用同一份定义，保证双端入口完全一致，不会各写一套而漂移。
  static const _destinations = <({IconData icon, String label})>[
    (icon: LucideIcons.house, label: '首页'),
    (icon: LucideIcons.clapperboard, label: '短剧'),
    (icon: LucideIcons.library_big, label: '书架'),
    (icon: LucideIcons.circle_user_round, label: '我的'),
  ];

  /// 宽屏断点：窗口达到该宽度时把底部药丸换成左侧悬浮导航栏。
  /// 900 是桌面窗口/平板的最小可用宽度；低于它保持手机形态不动，
  /// 手机端布局逐像素不变。
  static const _wideShellBreakpoint = 900.0;

  /// 更宽的窗口：侧栏展开为「图标 + 文字」的扩展形态，文字不再挤在
  /// 图标下方那 11sp 的小标签里。
  static const _extendedShellBreakpoint = 1200.0;

  void _selectTab(int i) {
    if (i != _index) setState(() => _index = i);
  }

  @override
  void initState() {
    super.initState();
    _startBackend();
  }

  Future<void> _startBackend() async {
    setState(() {
      _backendError = null;
    });
    try {
      await (widget.backendStarter ?? BackendService.instance.start)();
      if (mounted) {
        setState(() => _backendReady = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _backendError = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_backendReady) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_backendError == null)
                    const CircularProgressIndicator()
                  else
                    Icon(
                      LucideIcons.triangle_alert,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  const SizedBox(height: 16),
                  Text(_backendError == null ? '正在启动本地服务...' : '启动失败'),
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CachedBooksPage(),
                      ),
                    ),
                    icon: const Icon(LucideIcons.download),
                    label: const Text('离线阅读'),
                  ),
                  if (_backendError != null) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _backendError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _startBackend,
                      child: const Text('重试'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    final palette = HomePalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDramaTab = _index == 1;
    final glassDark = isDark || isDramaTab;
    // 墨水屏模式：本 build 由 Theme 变化触发重建（上面读了 Theme.of），
    // 这里直接读 notifier 当前值即可拿到最新开关，不另加监听。
    final eink = einkModeNotifier.value;
    // 宽屏（桌面窗口 / 平板）：底部药丸换成左侧悬浮导航栏，四个 tab 不变；
    // 窄屏（手机）保持底部药丸，布局逐像素不变。窗口拖动跨断点时
    // MediaQuery 变化会自然重建，不需要额外监听。
    final wideShell =
        MediaQuery.sizeOf(context).width >= _wideShellBreakpoint;
    final navBar = NavigationBarTheme(
      data: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: eink
            ? Colors.black
            : HomePalette.accent.withValues(
                alpha: glassDark ? 0.20 : 0.12,
              ),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? (eink
                      ? Colors.white
                      : HomePalette.accent)
                : (eink
                      ? Colors.black
                      : (glassDark
                            ? Colors.white.withValues(alpha: 0.65)
                            : palette.muted)),
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? (eink
                      ? Colors.black
                      : (glassDark
                            ? HomePalette.accent
                            : palette.accentText))
                : (eink
                      ? Colors.black
                      : (glassDark
                            ? Colors.white.withValues(alpha: 0.65)
                            : palette.muted)),
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        backgroundColor: Colors.transparent,
        elevation: 0,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.icon),
              label: d.label,
            ),
        ],
      ),
    );

    // 状态栏图标亮度挂在壳层、按选中 tab 切换：短剧页是黑底视频流（官方
    // SeriesMallFragment 的透明顶栏直接压在 feed 上），深色图标在黑底上
    // 整条状态栏都看不见，必须浅色；其余三页浅色底用深色。样式放壳层而不是
    // 各页内部，是因为 IndexedStack 里未选中的页不参与绘制，页内
    // AnnotatedRegion 切走后会残留上一个页的样式。
    final body = AnnotatedRegion<SystemUiOverlayStyle>(
      value: _index == 1
          ? SystemUiOverlayStyle.light
          : (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark),
      child: LazyIndexedStack(
        index: _index,
        children: [
          const HomePage(),
          const DramaPage(),
          // 空书架上的「去书城找书」切回首页 tab。
          LibraryPage(onBrowse: () => setState(() => _index = 0)),
          const MinePage(),
        ],
      ),
    );

    if (wideShell) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _wideRail(eink: eink, glassDark: glassDark, palette: palette),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: body,
      bottomNavigationBar: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: RepaintBoundary(
            child: _floatingSurface(
              eink: eink,
              glassDark: glassDark,
              child: navBar,
            ),
          ),
        ),
      ),
    );
  }

  /// 壳层悬浮面（底部药丸与宽屏侧栏共用）：圆角 28 的毛玻璃盒，或墨水屏
  /// 模式的实线白盒。抽成一份是为了两端控件视觉同源，不各写一套装饰。
  Widget _floatingSurface({
    required Widget child,
    required bool eink,
    required bool glassDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        // 墨水屏：阴影是灰阶 + 刷新残影来源，直接去掉，改用实线边框。
        boxShadow: eink
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: glassDark ? 0.38 : 0.08,
                  ),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: HomePalette.accent.withValues(
                    alpha: glassDark ? 0.06 : 0.03,
                  ),
                  blurRadius: 14,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        // 墨水屏：BackdropFilter 毛玻璃会把悬浮面变成一团灰，改实色。
        child: eink
            ? Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.black,
                    width: 0.8,
                  ),
                ),
                child: child,
              )
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  decoration: BoxDecoration(
                    color: glassDark
                        ? const Color(0xFF161619).withValues(alpha: 0.72)
                        : Colors.white.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: glassDark
                          ? Colors.white.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.75),
                      width: 0.8,
                    ),
                  ),
                  child: child,
                ),
              ),
      ),
    );
  }

  /// 宽屏左侧悬浮导航栏：与底部药丸同一批 destination、同一套主题数据，
  /// 只是竖排。≥1200 时展开为「图标 + 文字」的扩展形态。
  Widget _wideRail({
    required bool eink,
    required bool glassDark,
    required HomePalette palette,
  }) {
    final extended =
        MediaQuery.sizeOf(context).width >= _extendedShellBreakpoint;
    final rail = NavigationRail(
      selectedIndex: _index,
      onDestinationSelected: _selectTab,
      extended: extended,
      // 扩展态下框架断言 labelType 只能是 none：标签由扩展形态自带。
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      backgroundColor: Colors.transparent,
      indicatorColor: eink
          ? Colors.black
          : HomePalette.accent.withValues(
              alpha: glassDark ? 0.20 : 0.12,
            ),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      selectedIconTheme: IconThemeData(
        size: 22,
        color: eink ? Colors.white : HomePalette.accent,
      ),
      unselectedIconTheme: IconThemeData(
        size: 22,
        color: eink
            ? Colors.black
            : (glassDark
                  ? Colors.white.withValues(alpha: 0.65)
                  : palette.muted),
      ),
      selectedLabelTextStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: eink
            ? Colors.black
            : (glassDark ? HomePalette.accent : palette.accentText),
      ),
      unselectedLabelTextStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: eink
            ? Colors.black
            : (glassDark
                  ? Colors.white.withValues(alpha: 0.65)
                  : palette.muted),
      ),
      destinations: [
        for (final d in _destinations)
          NavigationRailDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.icon),
            label: Text(d.label),
          ),
      ],
    );
    return SafeArea(
      top: false,
      left: false,
      right: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
        child: RepaintBoundary(
          child: _floatingSurface(
            eink: eink,
            glassDark: glassDark,
            child: Column(
              children: [
                _railHeader(
                  eink: eink,
                  palette: palette,
                  extended: extended,
                ),
                Expanded(child: rail),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 侧边栏顶部品牌区：Logo + 应用名。扩展态横排，折叠态居中显示 Logo。
  Widget _railHeader({
    required bool eink,
    required HomePalette palette,
    required bool extended,
  }) {
    final accent = eink ? Colors.black : HomePalette.accent;
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/images/app_logo.webp',
        width: 32,
        height: 32,
        fit: BoxFit.contain,
        color: eink ? Colors.black : null,
      ),
    );
    return SizedBox(
      height: 56,
      child: extended
          ? Padding(
              padding: const EdgeInsets.only(left: 18, right: 16),
              child: Row(
                children: [
                  logo,
                  const SizedBox(width: 12),
                  Text(
                    'fqapp',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ],
              ),
            )
          : Center(child: logo),
    );
  }
}
