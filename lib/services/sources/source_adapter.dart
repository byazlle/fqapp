import '../../models/content_source.dart';
import '../../models/source_item.dart';
import '../content_source_store.dart';
import 'cms_source_client.dart';
import 'hema_source_adapter.dart';
import 'xifan_source_adapter.dart';

/// 一家内容源的适配器。页面只调这组方法，不直接碰各家字段。
abstract class SourceAdapter {
  ContentSource get source;

  bool supports(String kind) => source.supports(kind);

  Future<List<SourceItem>> browse(
    String kind, {
    String? category,
    int page = 1,
  });

  Future<List<SourceItem>> search(String kind, String query, {int page = 1});

  Future<SourceDetail> detail(String kind, String id);
}

/// 通用 CMS（苹果 CMS / TVBox）适配器：目前唯一完整接入的第三方协议。
class CmsSourceAdapter extends SourceAdapter {
  CmsSourceAdapter(this.source, {CmsSourceClient? client})
    : _client = client ?? CmsSourceClient(source.baseUrl);

  @override
  final ContentSource source;

  final CmsSourceClient _client;

  @override
  Future<List<SourceItem>> browse(
    String kind, {
    String? category,
    int page = 1,
  }) async {
    final items = await _client.list(category: category, page: page);
    return [
      for (final item in items)
        SourceItem(
          id: item.id,
          title: item.name,
          sourceId: source.id,
          kind: kind,
          cover: item.cover,
          remarks: item.remarks,
        ),
    ];
  }

  @override
  Future<List<SourceItem>> search(
    String kind,
    String query, {
    int page = 1,
  }) async {
    final items = await _client.search(query, page: page);
    return [
      for (final item in items)
        SourceItem(
          id: item.id,
          title: item.name,
          sourceId: source.id,
          kind: kind,
          cover: item.cover,
          remarks: item.remarks,
        ),
    ];
  }

  @override
  Future<SourceDetail> detail(String kind, String id) async {
    final detail = await _client.detail(id);
    if (detail == null) {
      throw const SourceException('没有取到详情，来源可能已失效');
    }
    return SourceDetail(
      id: detail.id,
      title: detail.name,
      sourceId: source.id,
      cover: detail.cover,
      description: detail.description,
      typeName: detail.typeName,
      year: detail.year,
      area: detail.area,
      remarks: detail.remarks,
      groups: [
        for (final group in detail.groups)
          SourceGroup(
            name: group.name,
            episodes: [
              for (final episode in group.episodes)
                SourceEpisode(name: episode.name, url: episode.url),
            ],
          ),
      ],
    );
  }
}

/// 接口已保留、但适配器尚未实现的来源（目前是红果网页版）。
/// 选中时会明确提示，而不是静默回退。
class PendingSourceAdapter extends SourceAdapter {
  PendingSourceAdapter(this.source);

  @override
  final ContentSource source;

  Never _pending() =>
      throw SourceException('「${source.name}」的适配器尚未接入，当前可用的是 CMS 自定义源');

  @override
  Future<List<SourceItem>> browse(
    String kind, {
    String? category,
    int page = 1,
  }) async => _pending();

  @override
  Future<List<SourceItem>> search(String kind, String query, {int page = 1}) async =>
      _pending();

  @override
  Future<SourceDetail> detail(String kind, String id) async => _pending();
}

class RoutedResult<T> {
  const RoutedResult({required this.value, required this.source, this.fellBack = false});

  final T value;
  final ContentSource source;
  final bool fellBack;
}

/// 按内容类型选源 + 自动容错。只负责视频类第三方源；番茄源仍走现有流程。
class SourceRouter {
  SourceRouter({ContentSourceStore? store, this.adapterFactory})
    : _store = store ?? ContentSourceStore.instance;

  final ContentSourceStore _store;

  /// 测试/扩展用的适配器工厂；返回 null 表示按协议走默认适配器。
  final SourceAdapter? Function(ContentSource source)? adapterFactory;

  SourceAdapter? adapterFor(ContentSource source) {
    if (!source.enabled) return null;
    // 远程屏蔽名单命中的源一律不接请求（设置里也打不开）。
    if (_store.isBlocked(source)) return null;
    final custom = adapterFactory?.call(source);
    if (custom != null) return custom;
    return switch (source.protocol) {
      SourceProtocol.cms => CmsSourceAdapter(source),
      SourceProtocol.xifan => XifanSourceAdapter(source),
      SourceProtocol.hema => HemaSourceAdapter(source),
      SourceProtocol.fanqie => null,
      SourceProtocol.hongguoWeb => PendingSourceAdapter(source),
    };
  }

  SourceAdapter? adapterForId(String sourceId) {
    final source = _store.sourceById(sourceId);
    return source == null ? null : adapterFor(source);
  }

  List<ContentSource> _chain(String kind) {
    if (!_store.autoFallback) return [_store.activeFor(kind)];
    return _store.fallbackChain(kind);
  }

  Future<RoutedResult<List<SourceItem>>> browse(
    String kind, {
    String? category,
    int page = 1,
  }) => _run(
    kind,
    (adapter) => adapter.browse(kind, category: category, page: page),
  );

  Future<RoutedResult<List<SourceItem>>> search(
    String kind,
    String query, {
    int page = 1,
  }) => _run(kind, (adapter) => adapter.search(kind, query, page: page));

  Future<RoutedResult<T>> _run<T>(
    String kind,
    Future<T> Function(SourceAdapter adapter) action,
  ) async {
    final chain = _chain(kind);
    final activeId = _store.activeFor(kind).id;
    Object? last;
    for (final source in chain) {
      final adapter = adapterFor(source);
      if (adapter == null) continue;
      try {
        return RoutedResult(
          value: await action(adapter),
          source: source,
          fellBack: source.id != activeId,
        );
      } catch (error) {
        last = error;
      }
    }
    if (last is SourceException) throw last;
    throw SourceException(
      last == null ? '当前类型没有可用的第三方来源' : '$last',
    );
  }

  Future<SourceDetail> detail(String sourceId, String kind, String id) async {
    final adapter = adapterForId(sourceId);
    if (adapter == null) {
      throw const SourceException('来源已关闭或不存在，请回到设置重新选择');
    }
    return adapter.detail(kind, id);
  }
}
