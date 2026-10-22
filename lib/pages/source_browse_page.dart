import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../models/content_source.dart';
import '../models/media_item.dart';
import '../models/series_detail.dart';
import '../models/source_item.dart';
import '../services/sources/source_adapter.dart';
import '../widgets/brand/fused_app_bar.dart';
import '../widgets/home/home_design.dart';
import 'player_page.dart';

/// 第三方来源的浏览页：搜索 / 列表 / 分页，点击进入详情。
///
/// 番茄源不在这里走：它已有首页、搜索、详情与播放链路；本页只服务
/// CMS 等第三方源，避免把两套模型硬塞进现有番茄页面。
class SourceBrowsePage extends StatefulWidget {
  const SourceBrowsePage({
    super.key,
    required this.source,
    required this.kind,
    this.router,
  });

  final ContentSource source;
  final String kind;
  final SourceRouter? router;

  @override
  State<SourceBrowsePage> createState() => _SourceBrowsePageState();
}

class _SourceBrowsePageState extends State<SourceBrowsePage> {
  late final SourceRouter _router = widget.router ?? SourceRouter();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final List<SourceItem> _items = [];
  ContentSource _resolvedSource = const ContentSource(
    id: '',
    name: '',
    protocol: SourceProtocol.cms,
  );
  String _query = '';
  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolvedSource = widget.source;
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || _loadingMore) return;
    if (!reset && !_hasMore) return;
    setState(() {
      if (reset) {
        _loading = true;
        _page = 1;
        _items.clear();
        _hasMore = true;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });
    try {
      final page = reset ? 1 : _page + 1;
      final result = _query.isEmpty
          ? await _router.browse(widget.kind, page: page)
          : await _router.search(widget.kind, _query, page: page);
      if (!mounted) return;
      setState(() {
        _resolvedSource = result.source;
        _page = page;
        _items.addAll(result.value);
        _hasMore = result.value.isNotEmpty;
        _loading = false;
        _loadingMore = false;
      });
      if (result.fellBack) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('当前源不可用，已自动切换到「${result.source.name}」')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _submitSearch(String value) {
    _query = value.trim();
    unawaited(_load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final palette = HomePalette.of(context);
    return FusedScrollMeter(
      child: Scaffold(
        backgroundColor: palette.ambientCanvas,
        appBar: FusedAppBar(
          title: Text('${_resolvedSource.name} · ${contentKindLabels[widget.kind] ?? ''}'),
          centerTitle: false,
          canvas: palette.ambientCanvas,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: TextField(
                key: const Key('source_search_field'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: _submitSearch,
                decoration: InputDecoration(
                  hintText: '在「${_resolvedSource.name}」里搜索',
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空',
                          onPressed: () {
                            _search.clear();
                            _submitSearch('');
                          },
                          icon: const Icon(LucideIcons.x, size: 16),
                        ),
                  filled: true,
                  fillColor: palette.surface,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: palette.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: palette.line, width: 0.6),
                  ),
                ),
              ),
            ),
            Expanded(child: _body(palette)),
          ],
        ),
      ),
    );
  }

  Widget _body(HomePalette palette) {
    if (_loading) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: HomePalette.accent,
          ),
        ),
      );
    }
    if (_error != null && _items.isEmpty) {
      return _state(
        palette,
        icon: LucideIcons.wifi_off,
        title: '来源暂时不可用',
        message: _error!,
        action: TextButton.icon(
          onPressed: () => _load(reset: true),
          icon: const Icon(LucideIcons.refresh_cw, size: 16),
          label: const Text('重试'),
        ),
      );
    }
    if (_items.isEmpty) {
      return _state(
        palette,
        icon: LucideIcons.search_x,
        title: _query.isEmpty ? '这个来源暂时没有内容' : '没有找到「$_query」',
        message: _query.isEmpty ? '可以换个来源，或稍后重试。' : '换个关键词试试。',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1280
            ? 7
            : width >= 1024
            ? 6
            : width >= 760
            ? 5
            : width >= 520
            ? 4
            : 3;
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.58,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final item = _items[index];
                  return _SourceCard(
                    item: item,
                    palette: palette,
                    onTap: () => _openDetail(item),
                  );
                }, childCount: _items.length),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: Center(
                  child: _loadingMore
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: HomePalette.accent,
                          ),
                        )
                      : _hasMore
                      ? TextButton.icon(
                          onPressed: () => _load(reset: false),
                          icon: const Icon(LucideIcons.chevron_down, size: 16),
                          label: const Text('加载更多'),
                        )
                      : Text(
                          '已经到底了',
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 12,
                          ),
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openDetail(SourceItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SourceDetailPage(
          source: _resolvedSource,
          kind: widget.kind,
          item: item,
          router: _router,
        ),
      ),
    );
  }

  Widget _state(
    HomePalette palette, {
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: palette.muted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.muted,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 10), action],
          ],
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.item,
    required this.palette,
    required this.onTap,
  });

  final SourceItem item;
  final HomePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: palette.soft),
                    if (item.cover.isNotEmpty)
                      Image.network(
                        item.cover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Center(
                          child: Icon(
                            LucideIcons.image_off,
                            size: 22,
                            color: palette.muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.ink,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (item.remarks.isNotEmpty)
              Text(
                item.remarks,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.muted, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}

/// 详情 + 线路 / 分集选择。播放复用 `PlayerPage`，通过 `contentLoader`
/// 把 CMS 直链交给现有播放器，避免重写一套播放/鉴权/续播。
class SourceDetailPage extends StatefulWidget {
  const SourceDetailPage({
    super.key,
    required this.source,
    required this.kind,
    required this.item,
    this.router,
  });

  final ContentSource source;
  final String kind;
  final SourceItem item;
  final SourceRouter? router;

  @override
  State<SourceDetailPage> createState() => _SourceDetailPageState();
}

class _SourceDetailPageState extends State<SourceDetailPage> {
  late final SourceRouter _router = widget.router ?? SourceRouter();
  SourceDetail? _detail;
  bool _loading = true;
  String? _error;
  int _groupIndex = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _router.detail(
        widget.source.id,
        widget.kind,
        widget.item.id,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _groupIndex = 0;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HomePalette.of(context);
    return FusedScrollMeter(
      child: Scaffold(
        backgroundColor: palette.ambientCanvas,
        appBar: FusedAppBar(
          title: Text(widget.source.name),
          centerTitle: false,
          canvas: palette.ambientCanvas,
        ),
        body: _loading
            ? const Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: HomePalette.accent,
                  ),
                ),
              )
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _load,
                        icon: const Icon(LucideIcons.refresh_cw, size: 16),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              )
            : _content(palette, _detail!),
      ),
    );
  }

  Widget _content(HomePalette palette, SourceDetail detail) {
    final group = detail.groups.isEmpty
        ? null
        : detail.groups[_groupIndex.clamp(0, detail.groups.length - 1)];
    final meta = [
      if (detail.typeName.isNotEmpty) detail.typeName,
      if (detail.year.isNotEmpty) detail.year,
      if (detail.area.isNotEmpty) detail.area,
      if (detail.remarks.isNotEmpty) detail.remarks,
    ].join(' · ');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Poster(url: detail.cover, palette: palette),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.title,
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      meta,
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  ],
                  if (detail.description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      detail.description,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 12.5,
                        height: 1.6,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (detail.groups.length > 1) ...[
          const SizedBox(height: 20),
          Text(
            '播放线路',
            style: TextStyle(
              color: palette.ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < detail.groups.length; i++)
                ChoiceChip(
                  key: ValueKey('source_group_$i'),
                  label: Text(detail.groups[i].name),
                  selected: i == _groupIndex,
                  onSelected: (_) => setState(() => _groupIndex = i),
                  selectedColor: HomePalette.accent.withValues(alpha: 0.16),
                  showCheckmark: false,
                ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Text(
              '选集',
              style: TextStyle(
                color: palette.ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              group == null ? '暂无分集' : '共 ${group.episodes.length} 集',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (group == null || group.episodes.isEmpty)
          Text(
            '这个来源没有提供可播放的分集地址。',
            style: TextStyle(color: palette.muted, fontSize: 12.5),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < group.episodes.length; i++)
                _EpisodeChip(
                  key: ValueKey('source_episode_$i'),
                  label: group.episodes[i].name,
                  onTap: () => _play(detail, group, i),
                ),
            ],
          ),
        if (group != null && group.episodes.isNotEmpty) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('source_play_first'),
            onPressed: () => _play(detail, group, 0),
            style: FilledButton.styleFrom(
              backgroundColor: HomePalette.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
            ),
            icon: const Icon(LucideIcons.play, size: 18),
            label: const Text('从第 1 集开始播放'),
          ),
        ],
      ],
    );
  }

  void _play(SourceDetail detail, SourceGroup group, int startIndex) {
    final urls = <String, String>{};
    final eps = <Chapter>[];
    for (var i = 0; i < group.episodes.length; i++) {
      final id = 'g${_groupIndex}e$i';
      urls[id] = group.episodes[i].url;
      eps.add(
        Chapter(
          itemId: id,
          title: group.episodes[i].name,
          volumeName: group.name,
        ),
      );
    }
    if (eps.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          bookId: 'cms:${widget.source.id}:${detail.id}',
          kind: widget.kind,
          title: detail.title,
          cover: detail.cover,
          eps: eps,
          startIndex: startIndex.clamp(0, eps.length - 1),
          shortSeries: false,
          // 第三方源没有番茄的剧集详情/弹幕：给空实现，避免附属请求打到番茄。
          seriesLoader: (_) async => SeriesDetail.empty,
          contentLoader: (chapter) async => {
            'video_url': urls[chapter.itemId] ?? '',
            'key_hex': '',
          },
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url, required this.palette});

  final String url;
  final HomePalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ColoredBox(
            color: palette.soft,
            child: url.isEmpty
                ? Icon(LucideIcons.image, color: palette.muted)
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Icon(LucideIcons.image_off, color: palette.muted),
                  ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeChip extends StatelessWidget {
  const _EpisodeChip({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HomePalette.of(context);
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.line, width: 0.6),
          ),
          child: Text(
            label,
            style: TextStyle(color: palette.ink, fontSize: 12.5),
          ),
        ),
      ),
    );
  }
}
