import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_client.dart';
import '../services/app_theme.dart';
import '../services/brand.dart';
import '../services/audio_preferences.dart';
import '../services/backend_service.dart';
import '../services/book_open_preferences.dart';
import '../services/drama_mute_preferences.dart';
import '../services/home_feed_cache.dart';
import '../services/library_store.dart';
import '../services/poster_cache.dart';
import '../services/rank_cache.dart';
import '../services/ui_scale.dart';
import '../widgets/brand/fused_app_bar.dart';
import '../widgets/home/home_design.dart';
import 'about_page.dart';
import 'cached_books_page.dart';
import 'cached_dramas_page.dart';
import 'content_sources_page.dart';
import 'library_backup_page.dart';
import 'log_viewer_page.dart';
import 'settings_category_page.dart';
import 'system_tts_settings_page.dart';

/// Settings home: a list of category entries. Each category opens its own
/// page with one rounded card of setting rows.
///
/// 宽屏（≥900，与壳层导航断点一致）改为双列：左侧分类列表、右侧当前
/// 分类的设置内容，不再层层 push；窄屏保持钻取导航，手机形态不变。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 宽屏双列：左侧选中的分类。窄屏不使用（点击即 push 子页）。
  int _selectedCategory = 0;

  static const _wideBreakpoint = 900.0;

  @override
  Widget build(BuildContext context) {
    // 开关读的是 ValueNotifier：先把持久化的值读出来，读到后自动重绘。
    unawaited(BookOpenPreferences.instance.load());
    final palette = HomePalette.of(context);
    final categories = <SettingsCategory>[
      SettingsCategory(
        icon: LucideIcons.palette,
        title: '外观',
        subtitle: '深色模式、墨水屏模式、界面缩放',
        items: [_themeModeItem(), _einkModeItem(), _uiScaleItem()],
      ),
      SettingsCategory(
        icon: LucideIcons.globe,
        title: '内容源',
        subtitle: '短剧 / 漫剧 / 小说等分别选择来源，支持自动容错',
        pageBuilder: (_) => const ContentSourcesPage(),
        items: const [],
      ),
      SettingsCategory(
        icon: LucideIcons.book_open,
        title: '阅读',
        subtitle: '点书直达阅读器',
        items: [_directReaderItem()],
      ),
      SettingsCategory(
        icon: LucideIcons.headphones,
        title: '听书',
        subtitle: '切到其他窗口时继续播放、系统朗读',
        items: [
          _backgroundAudioItem(),
          SettingsItem(
            icon: LucideIcons.mic,
            title: '系统朗读',
            subtitle: '选择 TTS 引擎与语速，支持本地书',
            onTap: (context, setState) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SystemTtsSettingsPage()),
            ),
          ),
        ],
      ),
      SettingsCategory(
        icon: LucideIcons.film,
        title: '短剧',
        subtitle: '播放',
        items: [_muteWhenColdStartItem()],
      ),
      SettingsCategory(
        icon: LucideIcons.database,
        title: '数据',
        subtitle: '备份与恢复、缓存、阅读与播放历史',
        items: [
          SettingsItem(
            icon: LucideIcons.database,
            title: '备份与恢复',
            subtitle: '导出收藏和进度，迁移到另一台设备',
            onTap: (context, setState) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LibraryBackupPage()),
            ),
          ),
          SettingsItem(
            icon: LucideIcons.book_check,
            title: '章节缓存',
            subtitle: '离线续读、查看占用和清理缓存',
            onTap: (context, setState) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CachedBooksPage()),
            ),
          ),
          SettingsItem(
            icon: LucideIcons.clapperboard,
            title: '剧集离线缓存',
            subtitle: '短剧下载、离线播放和清理缓存',
            onTap: (context, setState) => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CachedDramasPage()),
            ),
          ),
          SettingsItem(
            icon: LucideIcons.folder_open,
            title: '缓存目录',
            subtitle: '打开程序缓存所在文件夹',
            onTap: (context, setState) => _openCacheDir(context),
          ),
          SettingsItem(
            icon: LucideIcons.eraser,
            title: '清除缓存',
            subtitle: '清理图片与首页/榜单缓存（不影响书架与历史）',
            onTap: (context, setState) => _confirmClear(
              context,
              '清除缓存',
              '确定清除图片缓存和首页/榜单缓存吗？不会影响你的书架、收藏与历史。',
              _clearCaches,
            ),
          ),
          SettingsItem(
            icon: LucideIcons.folder_input,
            title: '缓存位置',
            subtitle: '更改缓存/数据存放目录（重启后生效）',
            onTap: (context, setState) => _relocateCacheDialog(context),
          ),
          _clearHistItem(),
        ],
      ),
      SettingsCategory(
        icon: LucideIcons.cpu,
        title: '服务',
        subtitle: '本地后端状态',
        items: [_backendItem(), _statusItem(), _logItem()],
      ),
      SettingsCategory(
        icon: LucideIcons.info,
        title: '关于',
        subtitle: '版本与应用信息',
        pageBuilder: (_) => const AboutPage(),
        items: const [],
      ),
    ];

    const categoryColors = [
      Brand.primary, // 外观
      Color(0xFF0EA5E9), // 内容源
      Color(0xFF14B8A6), // 阅读
      Color(0xFF8B5CF6), // 听书
      Color(0xFFF59E0B), // 短剧
      Color(0xFF3B82F6), // 数据
      Color(0xFF10B981), // 服务
      Color(0xFF6366F1), // 关于
    ];

    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    if (wide) {
      return FusedScrollMeter(
        child: Scaffold(
        backgroundColor: palette.canvas,
        appBar: FusedAppBar(
          title: const Text('设置'),
          centerTitle: true,
          canvas: palette.canvas,
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 300,
              child: _categoryList(categories, categoryColors),
            ),
            VerticalDivider(width: 1, thickness: 0.6, color: palette.line),
            Expanded(
              child: _categoryDetail(categories[_selectedCategory]),
            ),
          ],
        ),
        ),
      );
    }

    return FusedScrollMeter(
      child: Scaffold(
      backgroundColor: palette.canvas,
      appBar: FusedAppBar(
        title: const Text('设置'),
        centerTitle: true,
        canvas: palette.canvas,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Material(
            color: palette.surface,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: palette.line,
                  width: 0.6,
                ),
              ),
              child: Column(
              children: [
                for (var i = 0; i < categories.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 68,
                      color: palette.line,
                    ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: (i < categoryColors.length
                                ? categoryColors[i]
                                : HomePalette.accent)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        categories[i].icon,
                        size: 20,
                        color: i < categoryColors.length
                            ? categoryColors[i]
                            : HomePalette.accent,
                      ),
                    ),
                    title: Text(
                      categories[i].title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: palette.ink,
                      ),
                    ),
                    subtitle: Text(
                      categories[i].subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: palette.muted,
                      ),
                    ),
                    trailing: Icon(
                      LucideIcons.chevron_right,
                      size: 18,
                      color: palette.muted,
                    ),
                    onTap: () {
                      final cat = categories[i];
                      final pageBuilder = cat.pageBuilder;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              pageBuilder ??
                              (_) => SettingsCategoryPage(
                                title: cat.title,
                                items: cat.items,
                              ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
      ),
      ),
    );
  }

  /// 宽屏左列：分类导航。选中项用主色浅底圆角标出，点击只切右列内容，
  /// 不再 push 子页——双列的意义就在于少一层导航。
  Widget _categoryList(
    List<SettingsCategory> categories,
    List<Color> colors,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: categories.length,
      itemBuilder: (context, i) {
        final cat = categories[i];
        final selected = i == _selectedCategory;
        final accent = i < colors.length ? colors[i] : HomePalette.accent;
        final palette = HomePalette.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: selected
                ? HomePalette.accent.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              selected: selected,
              selectedTileColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(cat.icon, size: 20, color: accent),
              ),
              title: Text(
                cat.title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: palette.ink,
                ),
              ),
              subtitle: Text(
                cat.subtitle,
                style: TextStyle(fontSize: 12.5, color: palette.muted),
              ),
              onTap: () {
                if (i != _selectedCategory) {
                  setState(() => _selectedCategory = i);
                }
              },
            ),
          ),
        );
      },
    );
  }

  /// 宽屏右列：当前分类的设置内容，卡片样式与窄端子页一致。
  /// [SettingsCategory.pageBuilder] 分类（关于）直接内嵌它的页面。
  Widget _categoryDetail(SettingsCategory cat) {
    final pageBuilder = cat.pageBuilder;
    if (pageBuilder != null) return pageBuilder(context);
    final palette = HomePalette.of(context);
    return StatefulBuilder(
      builder: (context, setState) => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Material(
            color: palette.surface,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.line, width: 0.6),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < cat.items.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, indent: 68, color: palette.line),
                    settingsItemRow(context, cat.items[i], setState),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 外观 ──────────────────────────────────────────────────────────────

  SettingsItem _themeModeItem() => SettingsItem(
    icon: LucideIcons.sun_moon,
    title: '深色模式',
    trailingBuilder: (context) => ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _modeLabel(mode),
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(width: 4),
          const Icon(LucideIcons.chevron_right, size: 18),
        ],
      ),
    ),
    onTap: (context, setState) => _showThemeModeDialog(context),
  );

  String _modeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  Future<void> _showThemeModeDialog(BuildContext context) async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('深色模式'),
        children: [
          RadioGroup<ThemeMode>(
            groupValue: themeModeNotifier.value,
            onChanged: (v) {
              if (v != null) Navigator.pop(c, v);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in const [
                  ThemeMode.system,
                  ThemeMode.light,
                  ThemeMode.dark,
                ])
                  RadioListTile<ThemeMode>(
                    value: m,
                    title: Text(_modeLabel(m)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;
    themeModeNotifier.value = selected;
    try {
      final sp = await SharedPreferences.getInstance();
      if (!await sp.setString(themeModeKey, selected.name)) {
        throw StateError('Theme preference was not saved');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('外观已更新，但未能保存')));
      }
    }
  }

  /// #15/#9 墨水屏模式：纯黑白、无毛玻璃、无过渡动画。开启时强制浅色，
  /// 深色模式恢复后仍按原设置生效。
  SettingsItem _einkModeItem() => SettingsItem(
    icon: LucideIcons.book_open,
    title: '墨水屏模式',
    subtitle: '纯黑白、无毛玻璃、无过渡动画，适合墨水屏设备',
    trailingBuilder: (context) => ValueListenableBuilder<bool>(
      valueListenable: einkModeNotifier,
      builder: (context, value, _) => Switch(
        value: value,
        onChanged: (v) => unawaited(_setEinkMode(context, v)),
      ),
    ),
    onTap: (context, setState) {
      unawaited(_setEinkMode(context, !einkModeNotifier.value));
    },
  );

  Future<void> _setEinkMode(BuildContext context, bool value) async {
    einkModeNotifier.value = value;
    try {
      final sp = await SharedPreferences.getInstance();
      if (!await sp.setBool(einkModeKey, value)) {
        throw StateError('E-ink preference was not saved');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('墨水屏模式已更新，但未能保存')));
      }
    }
  }

  /// 应用内界面缩放：整体（文字 + 布局）一起缩放，类似浏览器缩放。
  /// 与系统 DPI 独立，适合高分屏想一屏看更多内容、或远距离想放大界面。
  SettingsItem _uiScaleItem() => SettingsItem(
    icon: LucideIcons.zoom_in,
    title: '界面缩放',
    subtitle: '整体放大或缩小界面，适合高分屏与大字号',
    trailingBuilder: (context) => ValueListenableBuilder<double>(
      valueListenable: uiScaleNotifier,
      builder: (context, value, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            uiScaleLabel(value),
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(width: 4),
          const Icon(LucideIcons.chevron_right, size: 18),
        ],
      ),
    ),
    onTap: (context, setState) => _showUiScaleDialog(context),
  );

  Future<void> _showUiScaleDialog(BuildContext context) async {
    final selected = await showDialog<double>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('界面缩放'),
        children: [
          RadioGroup<double>(
            groupValue: uiScaleNotifier.value,
            onChanged: (v) {
              if (v != null) Navigator.pop(c, v);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in uiScaleOptions)
                  RadioListTile<double>(
                    value: option,
                    title: Text(uiScaleLabel(option)),
                    subtitle: option == 1.0
                        ? const Text('默认，界面按 100% 显示')
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;
    uiScaleNotifier.value = clampUiScale(selected);
    try {
      final sp = await SharedPreferences.getInstance();
      if (!await sp.setDouble(uiScaleKey, uiScaleNotifier.value)) {
        throw StateError('UI scale preference was not saved');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('界面缩放已更新，但未能保存')));
      }
    }
  }

  // ── 阅读 ──────────────────────────────────────────────────────────────

  /// issue #19 第 3 条：点书跳过详情页，直接按上次进度进阅读器（小说/漫画）。
  /// 默认关＝现有行为（先进详情页）。听书/短剧与加载失败时仍停留在详情页。
  SettingsItem _directReaderItem() => SettingsItem(
    icon: LucideIcons.book_open,
    title: '点击书籍直接进入阅读',
    subtitle: '点书架、首页、搜索里的书时，跳过详情页直接开始阅读',
    trailingBuilder: (context) => ValueListenableBuilder<bool>(
      valueListenable: BookOpenPreferences.instance.directReader,
      builder: (context, value, _) => Switch(
        value: value,
        onChanged: (v) => unawaited(BookOpenPreferences.instance.set(v)),
      ),
    ),
    onTap: (context, setState) {
      final current = BookOpenPreferences.instance.directReader.value;
      unawaited(BookOpenPreferences.instance.set(!current));
    },
  );
  // ── 听书 ──────────────────────────────────────────────────────────────

  SettingsItem _backgroundAudioItem() => SettingsItem(
    icon: LucideIcons.radio,
    title: '后台听书',
    subtitle: '切到其他窗口或最小化时继续播放',
    trailingBuilder: (context) => ValueListenableBuilder<bool>(
      valueListenable: AudioPreferences.instance.backgroundPlayback,
      builder: (context, value, _) => Switch(
        value: value,
        onChanged: (v) => unawaited(AudioPreferences.instance.setBackgroundPlayback(v)),
      ),
    ),
    onTap: (context, setState) {
      final current = AudioPreferences.instance.backgroundPlayback.value;
      unawaited(AudioPreferences.instance.setBackgroundPlayback(!current));
    },
  );

  // ── 短剧 ──────────────────────────────────────────────────────────────

  /// 官方设置项「开启应用时默认静音」（`GlobalMuteConfig` 标题，持久层
  /// `open_mute_when_cold_start`，默认 false＝有声起播）。
  SettingsItem _muteWhenColdStartItem() => SettingsItem(
    icon: LucideIcons.volume_x,
    title: '开启应用时默认静音',
    subtitle: '进入短剧时静音播放，可在播放页取消',
    // Switch 走 ValueListenableBuilder，翻转后无需依赖页面的 setState。
    trailingBuilder: (context) => ValueListenableBuilder<bool>(
      valueListenable: DramaMutePreferences.instance.muteWhenColdStart,
      builder: (context, value, _) => Switch(
        value: value,
        onChanged: (v) => unawaited(DramaMutePreferences.instance.set(v)),
      ),
    ),
    onTap: (context, setState) {
      final current = DramaMutePreferences.instance.muteWhenColdStart.value;
      unawaited(DramaMutePreferences.instance.set(!current));
    },
  );

  // ── 数据 ──────────────────────────────────────────────────────────────

  SettingsItem _clearHistItem() => SettingsItem(
    icon: LucideIcons.trash,
    title: '清空历史',
    subtitle: '删除全部阅读/播放历史与累计时长',
    onTap: (context, setState) => _confirmClear(
      context,
      '清空历史',
      '确定清空全部阅读/播放历史与累计时长吗？',
      LibraryStore.instance.clearReadingData,
    ),
  );

  Future<void> _confirmClear(
    BuildContext context,
    String title,
    String message,
    Future<void> Function() action,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await action();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已清空')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('清空失败，请重试')));
      }
    }
  }

  // ── 缓存管理 ────────────────────────────────────────────────────────

  /// 与 main.dart 中 Hive 初始化使用的覆盖键保持一致。
  static const _cacheDirOverrideKey = 'cacheDirOverride';

  /// 当前生效的缓存/数据目录：若用户在设置中迁移过则取其覆盖值，
  /// 否则为默认的应用支持目录（Windows 上即 %APPDATA%\byazlle\FanqieDuanwan）。
  Future<String> _activeCacheDir() async {
    final sp = await SharedPreferences.getInstance();
    final override = sp.getString(_cacheDirOverrideKey);
    if (override != null && override.isNotEmpty) return override;
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  Future<void> _openCacheDir(BuildContext context) async {
    final path = await _activeCacheDir();
    final dir = io.Directory(path);
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (_) {}
    }
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.file(path),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开缓存目录')));
    }
  }

  /// 清除不影响用户数据的缓存：图片缓存 + 首页/榜单 feed 缓存。
  Future<void> _clearCaches() async {
    try {
      await PosterCache.instance.emptyCache();
    } catch (_) {}
    try {
      await HomeFeedCache.instance.clear();
    } catch (_) {}
    try {
      await RankCache.instance.clear();
    } catch (_) {}
  }

  Future<void> _relocateCacheDialog(BuildContext context) async {
    final current = await _activeCacheDir();
    if (!context.mounted) return;
    final controller = TextEditingController(text: current);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('更改缓存位置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '输入新的缓存/数据目录（绝对路径）。确认后应用会：\n'
              '1. 安全迁移现有书架、历史、离线等数据到新目录；\n'
              '2. 自动重启以在新目录加载数据。\n\n'
              '注意：迁移到非默认目录后，卸载程序不会自动清除该目录；'
              '目录内会生成 fanqieduanwan-data.txt 说明文件，便于日后识别与手动清理。',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例如 D:\\FanqieDuanwanData',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('迁移并重启'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final target = controller.text.trim();
    if (target.isEmpty || target == current) return;

    // 安全迁移：先关闭所有 Hive box（落盘，避免复制撕裂写入），再复制到临时
    // 目录、校验，校验通过才原子移动到目标并写入 override，最后重启。任何
    // 一步失败都不写 override、不删源，重启后数据完好无损。
    try {
      await Hive.close();

      final source = io.Directory(current);
      final tempDir = io.Directory('$target.migrating');
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      if (await source.exists()) {
        await _copyDir(source, tempDir);
      } else {
        await tempDir.create(recursive: true);
      }

      final srcStats = await _dirStats(source);
      final tmpStats = await _dirStats(tempDir);
      final verified = srcStats.files == 0 ||
          (srcStats.files == tmpStats.files &&
              srcStats.bytes == tmpStats.bytes);
      if (!verified) {
        // 校验失败：不写 override、不删源，重启回原目录（数据完好）。
        if (!context.mounted) {
          io.exit(0);
        }
        await _migrationResultDialog(
          context,
          title: '迁移未完成',
          message: '数据校验失败，已取消迁移。请重启应用以恢复原数据。',
        );
        io.exit(0);
      }

      // 校验通过：temp -> target（跨卷时退化为复制），确有数据时再删源目录。
      final targetDir = io.Directory(target);
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
      await _moveOrCopy(tempDir, targetDir);
      if (srcStats.files > 0 && await source.exists()) {
        await source.delete(recursive: true);
      }

      final sp = await SharedPreferences.getInstance();
      await sp.setString(_cacheDirOverrideKey, target);
      // 在自定义目录留一份说明：卸载程序只清理默认目录，此目录需用户手动
      // 删除。文件本身不参与任何数据读写，只是给用户/排障一个明确标识。
      try {
        await io.File(
          '$target${io.Platform.pathSeparator}fanqieduanwan-data.txt',
        ).writeAsString(
          '此目录由 ${Brand.name} 的「更改缓存位置」迁移而来，'
          '存放书架、历史、离线缓存与图片缓存。\n'
          '卸载 ${Brand.name} 不会自动删除此目录；如需彻底清理，请手动删除整个目录。\n',
        );
      } catch (_) {}
      if (!context.mounted) {
        io.exit(0);
      }
      await _migrationResultDialog(
        context,
        title: '迁移完成',
        message: '数据已迁移到新目录，请重启应用以生效。',
      );
      io.exit(0);
    } catch (_) {
      if (!context.mounted) {
        io.exit(0);
      }
      await _migrationResultDialog(
        context,
        title: '迁移未完成',
        message: '迁移过程出错，已取消。请重启应用以恢复原数据。',
      );
      io.exit(0);
    }
  }

  /// 迁移结束弹窗：提示用户重启，点确定即退出进程（数据目录已切换，重启后
  /// 由 main 按 override 重新加载）。barrierDismissible=false 防止误触。
  Future<void> _migrationResultDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => io.exit(0),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ── 服务 ──────────────────────────────────────────────────────────────

  SettingsItem _backendItem() => SettingsItem(
    icon: LucideIcons.cpu,
    title: '本地后端',
    subtitle: BackendService.instance.baseUrl,
    // The adapter only answers a request that carries the per-launch
    // capability, and the entry URL is what hands it to a browser as a session
    // cookie. Opening the bare base URL would just land on a 401.
    onTap: (context, setState) => _openWebUi(context),
  );

  /// Opens the built-in Web UI in a browser.
  ///
  /// The transport's `resourceBase` carries the loopback capability in its
  /// path; the adapter answers that entry with a redirect to `/` plus the
  /// session cookie, so the capability never lingers in the address bar.
  Future<void> _openWebUi(BuildContext context) async {
    final entry = BackendService.instance.webUiEntryUrl;
    if (entry.isEmpty) return;
    var launched = false;
    try {
      // Android package visibility may hide a browser from canLaunchUrl even
      // though it can handle the actual ACTION_VIEW intent.
      launched = await launchUrl(
        Uri.parse(entry),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Report launch failures through the same visible fallback.
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开 Web UI')));
    }
  }

  SettingsItem _logItem() => SettingsItem(
    icon: LucideIcons.terminal,
    title: '日志',
    subtitle: '查看应用运行日志',
    onTap: (context, setState) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LogViewerPage()),
    ),
  );

  SettingsItem _statusItem() => SettingsItem(
    icon: LucideIcons.circle_check,
    title: '服务状态',
    rowBuilder: (context) => const _ServiceStatusRow(),
  );

  // ── 关于 ──────────────────────────────────────────────────────────────
  // The About category opens the About page directly via its pageBuilder;
  // no category-page items are needed.
}

/// Self-refreshing service status row (health check + refresh button).
class _ServiceStatusRow extends StatefulWidget {
  const _ServiceStatusRow();

  @override
  State<_ServiceStatusRow> createState() => _ServiceStatusRowState();
}

class _ServiceStatusRowState extends State<_ServiceStatusRow> {
  String _status = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final ok = await ApiClient.instance.health();
    if (!mounted) return;
    setState(() => _status = ok ? '运行中' : '已停止');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final healthy = _status == '运行中';
    return ListTile(
      leading: Icon(
        healthy ? LucideIcons.circle_check : LucideIcons.circle_alert,
        color: healthy ? Colors.green : Colors.red,
      ),
      title: Text('服务状态', style: theme.textTheme.titleMedium),
      subtitle: Text(
        _status,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(LucideIcons.rotate_ccw, size: 18),
        onPressed: _refresh,
      ),
    );
  }
}

// ── 缓存迁移辅助（与 _relocateCacheDialog 配套）────────────────────────
// 均为文件操作，与页面状态无关，抽成顶层函数便于单独测试与复用。

/// 递归复制目录（保留相对路径结构）。
Future<void> _copyDir(io.Directory source, io.Directory dest) async {
  await dest.create(recursive: true);
  await for (final entity in source.list(recursive: true)) {
    if (entity is io.File) {
      final relative = entity.path.substring(source.path.length);
      final newFile = io.File('${dest.path}$relative');
      await newFile.parent.create(recursive: true);
      await entity.copy(newFile.path);
    } else if (entity is io.Directory) {
      final relative = entity.path.substring(source.path.length);
      await io.Directory('${dest.path}$relative').create(recursive: true);
    }
  }
}

/// 统计目录内文件数与总字节数（用于迁移前后校验）。
Future<({int files, int bytes})> _dirStats(io.Directory dir) async {
  var files = 0;
  var bytes = 0;
  if (!await dir.exists()) return (files: 0, bytes: 0);
  await for (final entity in dir.list(recursive: true)) {
    if (entity is io.File) {
      try {
        final stat = await entity.stat();
        if (stat.type == io.FileSystemEntityType.file) {
          files++;
          bytes += stat.size;
        }
      } catch (_) {
        // 复制途中文件消失：不计、不阻断。
      }
    }
  }
  return (files: files, bytes: bytes);
}

/// 尽量原子移动；跨卷 rename 失败时退化为复制后删除源。
Future<void> _moveOrCopy(io.Directory from, io.Directory to) async {
  try {
    await from.rename(to.path);
  } on io.FileSystemException {
    await _copyDir(from, to);
    await from.delete(recursive: true);
  }
}
