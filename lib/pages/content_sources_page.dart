import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../models/content_source.dart';
import '../services/content_source_store.dart';
import '../services/source_blocklist_service.dart';
import '../widgets/brand/fused_app_bar.dart';
import '../widgets/home/home_design.dart';
import 'source_browse_page.dart';

/// 设置 → 内容源。
///
/// 每一类内容（短剧 / 漫剧 / 漫画 / 小说 / 听书）独立选择当前来源；第三方
/// 源默认关闭，用户开启后才参与切换。自定义源走通用 CMS 协议，地址由用户
/// 自行填写，应用不内置、不存储任何第三方内容地址。
class ContentSourcesPage extends StatefulWidget {
  const ContentSourcesPage({super.key});

  @override
  State<ContentSourcesPage> createState() => _ContentSourcesPageState();
}

class _ContentSourcesPageState extends State<ContentSourcesPage> {
  final _store = ContentSourceStore.instance;
  String _kind = 'video';

  @override
  void initState() {
    super.initState();
    unawaited(_store.load());
    // 打开设置页时顺带刷新远程屏蔽名单（有缓存先用缓存，拉取失败不打扰用户）。
    unawaited(SourceBlocklistService.instance.initialize());
  }

  @override
  Widget build(BuildContext context) {
    final palette = HomePalette.of(context);
    return FusedScrollMeter(
      child: Scaffold(
        backgroundColor: palette.ambientCanvas,
        appBar: FusedAppBar(
          title: const Text('内容源'),
          centerTitle: false,
          canvas: palette.ambientCanvas,
        ),
        body: ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            // 展示该类型下“声明支持”的全部源（含关闭的），关闭的也能重新打开；
            // 自动容错候选仍只看已启用的 `forKind`。
            final available = _store.allForKind(_kind);
            final activeId = _store.activeFor(_kind).id;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _Notice(palette: palette),
                const SizedBox(height: 14),
                _AutoFallbackCard(store: _store, palette: palette),
                const SizedBox(height: 18),
                _KindSelector(
                  selected: _kind,
                  onSelected: (kind) => setState(() => _kind = kind),
                ),
                const SizedBox(height: 14),
                if (available.isEmpty)
                  _EmptyState(palette: palette, kind: _kind)
                else
                  _SourceCard(
                    palette: palette,
                    children: [
                      for (final source in available)
                        _SourceRow(
                          key: ValueKey('source_${source.id}'),
                          source: source,
                          active: source.id == activeId,
                          blocked: _store.isBlocked(source),
                          blockedNotice: _store.blocklistNotice,
                          palette: palette,
                          onSelect: () => _store.setActive(_kind, source.id),
                          onToggle: source.id == defaultSourceId
                              ? null
                              : (value) => _store.setEnabled(source.id, value),
                          onDelete: source.builtin
                              ? null
                              : () => _confirmRemove(source),
                          onProbe: source.protocol == SourceProtocol.cms
                              ? () => _probe(source)
                              : null,
                        ),
                    ],
                  ),
                if (_kind == 'book' || _kind == 'audio') ...[
                  const SizedBox(height: 12),
                  Text(
                    '当前的第三方视频源不提供小说 / 听书内容；如需扩展，'
                    '需要接入单独的文本源适配器。',
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton.icon(
                  key: const Key('add_custom_source'),
                  onPressed: _kind == 'book' || _kind == 'audio'
                      ? null
                      : _showAddDialog,
                  style: FilledButton.styleFrom(
                    backgroundColor: HomePalette.accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: const Text('添加自定义 CMS 源'),
                ),
                const SizedBox(height: 8),
                Text(
                  '支持 `?ac=list` / `?ac=detail&ids=` 形式的苹果 CMS 兼容接口；'
                  '添加时会先探活。',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  key: const Key('browse_active_source'),
                  onPressed: _kind == 'video' || _kind == 'manju'
                      ? _browseActive
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.accentText,
                    side: BorderSide(color: palette.line),
                    minimumSize: const Size.fromHeight(44),
                  ),
                  icon: const Icon(LucideIcons.play, size: 17),
                  label: const Text('浏览当前来源'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _browseActive() {
    final active = _store.activeFor(_kind);
    if (active.protocol == SourceProtocol.fanqie) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('内置番茄源请直接使用首页 / 搜索 / 详情')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SourceBrowsePage(source: active, kind: _kind),
      ),
    );
  }

  Future<void> _probe(ContentSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('正在检测「${source.name}」…'), duration: const Duration(seconds: 1)),
    );
    final result = await _store.probe(source);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? '「${source.name}」连接正常（${result.elapsedMs}ms）'
              : '「${source.name}」不可用：${result.message}',
        ),
      ),
    );
  }

  Future<void> _confirmRemove(ContentSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除来源'),
        content: Text('确定删除「${source.name}」吗？删除后已保存的该源进度不会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _store.removeCustom(source.id);
  }

  Future<void> _showAddDialog() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    String? error;
    var busy = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('添加 CMS 源'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('custom_source_name'),
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如：我的线路 A',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('custom_source_url'),
                controller: urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '接口地址',
                  hintText: 'https://example.com/api.php/provide/vod/',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error!,
                  style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() {
                        busy = true;
                        error = null;
                      });
                      final source = await _store.addCustom(
                        name: nameController.text,
                        url: urlController.text,
                      );
                      if (source == null) {
                        setDialogState(() {
                          busy = false;
                          error = '名称不能为空；地址需为公网 http(s)、不重复，且未被远程名单停用';
                        });
                        return;
                      }
                      final result = await _store.probe(source);
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            result.ok
                                ? '已添加「${source.name}」，连接正常（${result.elapsedMs}ms）'
                                : '已添加「${source.name}」，但探活失败：${result.message}',
                          ),
                        ),
                      );
                    },
              child: Text(busy ? '检测中…' : '添加并检测'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    urlController.dispose();
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.palette});

  final HomePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.soft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line, width: 0.6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 16, color: palette.accentText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '内容源只决定「从哪里取内容」。第三方源默认关闭，开启前请自行确认其授权与可用性；'
              '本应用不内置、不存储、不转码任何第三方内容。',
              style: TextStyle(
                color: palette.muted,
                fontSize: 12,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoFallbackCard extends StatelessWidget {
  const _AutoFallbackCard({required this.store, required this.palette});

  final ContentSourceStore store;
  final HomePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Material 必须放在带背景色的 DecoratedBox 之内，否则 ListTile 的
      // 背景与点击涟漪会被盖住（debug 下框架会直接断言）。
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.line, width: 0.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: palette.surface,
        child: SwitchListTile(
        key: const Key('source_auto_fallback'),
        value: store.autoFallback,
        onChanged: (value) => unawaited(store.setAutoFallback(value)),
        title: Text(
          '自动容错',
          style: TextStyle(
            color: palette.ink,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '当前源超时或失败时，按顺序尝试同类型的其他已启用源',
          style: TextStyle(color: palette.muted, fontSize: 12),
        ),
          activeThumbColor: HomePalette.accent,
        ),
      ),
    );
  }
}

class _KindSelector extends StatelessWidget {
  const _KindSelector({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = HomePalette.of(context);
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final entry in contentKindLabels.entries) ...[
            ChoiceChip(
              key: ValueKey('source_kind_${entry.key}'),
              label: Text(entry.value),
              selected: selected == entry.key,
              onSelected: (_) => onSelected(entry.key),
              selectedColor: HomePalette.accent.withValues(alpha: 0.16),
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected == entry.key ? palette.accentText : palette.ink,
              ),
              side: BorderSide(
                color: selected == entry.key
                    ? HomePalette.accent.withValues(alpha: 0.5)
                    : palette.line,
              ),
              showCheckmark: false,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.palette, required this.children});

  final HomePalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: palette.line, width: 0.6),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    super.key,
    required this.source,
    required this.active,
    required this.palette,
    required this.onSelect,
    required this.onToggle,
    required this.onDelete,
    required this.onProbe,
    this.blocked = false,
    this.blockedNotice = '',
  });

  final ContentSource source;
  final bool active;
  final HomePalette palette;
  final VoidCallback onSelect;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onDelete;
  final VoidCallback? onProbe;

  /// 被远程屏蔽名单停用：不可选、打不开，只保留展示。
  final bool blocked;
  final String blockedNotice;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: source.enabled && !blocked ? onSelect : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              active
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: active ? HomePalette.accent : palette.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          source.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _Badge(
                        text: source.builtin ? '内置' : '自定义',
                        palette: palette,
                      ),
                      if (blocked) ...[
                        const SizedBox(width: 4),
                        _Badge(text: '已停用', palette: palette, warn: true),
                      ] else if (source.protocol != SourceProtocol.fanqie) ...[
                        const SizedBox(width: 4),
                        _Badge(text: '第三方', palette: palette, warn: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    blocked
                        ? blockedNotice
                        : (source.baseUrl.isEmpty
                              ? source.protocol.label
                              : '${source.protocol.label} · ${source.baseUrl}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            if (onProbe != null && !blocked)
              IconButton(
                key: ValueKey('probe_${source.id}'),
                tooltip: '检测连接',
                onPressed: onProbe,
                icon: Icon(LucideIcons.activity, size: 16, color: palette.muted),
              ),
            Switch(
              value: source.enabled && !blocked,
              onChanged: blocked ? null : onToggle,
              activeThumbColor: HomePalette.accent,
            ),
            if (onDelete != null && !blocked)
              IconButton(
                key: ValueKey('delete_${source.id}'),
                tooltip: '删除',
                onPressed: onDelete,
                icon: Icon(LucideIcons.trash, size: 16, color: palette.muted),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.palette, this.warn = false});

  final String text;
  final HomePalette palette;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final color = warn ? const Color(0xFFF59E0B) : palette.accentText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette, required this.kind});

  final HomePalette palette;
  final String kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.line, width: 0.6),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.inbox, size: 26, color: palette.muted),
          const SizedBox(height: 10),
          Text(
            '${contentKindLabels[kind] ?? '该类型'}暂无可用的第三方源',
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
