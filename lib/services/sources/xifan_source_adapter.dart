import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/content_source.dart';
import '../../models/source_item.dart';
import 'source_adapter.dart';

/// 西饭短剧适配器（接口形态取自 `jackotom/hongguo-drama` 的
/// `src/native/xifan.js`，仅重写协议，不复制其播放器/下载逻辑）。
///
/// - 列表：`/xifan/drama/portalPage` 的 `duanjuCategory` / `aggregationPage`
/// - 搜索：`/xifan/search/getSearchList`
/// - 详情：`/xifan/drama/getDuanjuInfo`
/// - 播放：详情里的 `episodeList[].playUrl`，仅 `unlock == true` 的分集可用
class XifanSourceAdapter extends SourceAdapter {
  XifanSourceAdapter(this.source, {http.Client? client})
    : _client = client ?? http.Client();

  @override
  final ContentSource source;

  final http.Client _client;

  static const _base = 'https://xifan-api-cn.youlishipin.com';
  static const _timeout = Duration(seconds: 10);
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Mozilla/5.0',
  };

  List<_XifanGenre>? _genresCache;

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> params,
  ) async {
    final uri = Uri.parse('$_base$path').replace(
      queryParameters: {
        ...params,
        'version': '2001001',
        'androidVersionCode': '28',
      },
    );
    late final http.Response response;
    try {
      response = await _client.get(uri, headers: _headers).timeout(_timeout);
    } catch (_) {
      throw const SourceException('西饭连接失败或超时');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SourceException('西饭 HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (decoded is! Map || decoded['ret'] != 0 || decoded['result'] is! Map) {
      throw const SourceException('西饭返回数据异常');
    }
    return Map<String, dynamic>.from(decoded['result'] as Map);
  }

  List<Map> _contents(Map<String, dynamic> result) {
    final elements = result['elements'];
    if (elements is! List) return const [];
    final out = <Map>[];
    for (final element in elements) {
      if (element is! Map) continue;
      final contents = element['contents'];
      if (contents is! List) continue;
      for (final item in contents) {
        if (item is Map) out.add(item);
      }
    }
    return out;
  }

  Future<List<_XifanGenre>> _genres() async {
    final cached = _genresCache;
    if (cached != null && cached.isNotEmpty) return cached;
    final result = await _get('/xifan/drama/portalPage', {
      'reqType': 'duanjuCategory',
    });
    final seen = <int>{};
    final genres = <_XifanGenre>[];
    for (final item in _contents(result)) {
      final category = item['categoryItemVo'];
      if (category is! Map) continue;
      final subs = category['subCategories'];
      final list = subs is List ? subs : [category];
      for (final sub in list) {
        if (sub is! Map) continue;
        final id = sub['categoryId'];
        final label = _plain(sub['oppoCategory']);
        if (id is! int || id <= 0 || label.isEmpty || !seen.add(id)) continue;
        genres.add(
          _XifanGenre(
            id: id,
            label: label,
            version: (sub['version'] as num?)?.toInt() ?? 1,
          ),
        );
      }
    }
    if (genres.isEmpty) throw const SourceException('西饭没有返回可用分类');
    _genresCache = genres;
    return genres;
  }

  @override
  Future<List<SourceItem>> browse(
    String kind, {
    String? category,
    int page = 1,
  }) async {
    final genres = await _genres();
    final selected = genres.firstWhere(
      (item) => item.label == category,
      orElse: () => genres.first,
    );
    final result = await _get('/xifan/drama/portalPage', {
      'reqType': 'aggregationPage',
      'offset': '${(page - 1) * 30}',
      'categoryId': '${selected.id}',
      'categoryNames': selected.label,
      'categoryVersion': '${selected.version}',
    });
    return _items(result, kind);
  }

  @override
  Future<List<SourceItem>> search(
    String kind,
    String query, {
    int page = 1,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const [];
    final result = await _get('/xifan/search/getSearchList', {
      'keyword': keyword,
      'pageIndex': '$page',
    });
    return _items(result, kind);
  }

  List<SourceItem> _items(Map<String, dynamic> result, String kind) {
    final seen = <String>{};
    final items = <SourceItem>[];
    for (final entry in _contents(result)) {
      final vo = entry['duanjuVo'];
      if (vo is! Map) continue;
      final sourceName = _plain(vo['source']);
      final duanjuId = _plain(vo['duanjuId']);
      final title = _plain(vo['title']);
      if (sourceName.isEmpty || duanjuId.isEmpty || title.isEmpty) continue;
      final id = 'xifan:$sourceName:$duanjuId';
      if (!seen.add(id)) continue;
      items.add(
        SourceItem(
          id: id,
          title: title,
          sourceId: source.id,
          kind: kind,
          cover: _https(vo['coverImageUrl']),
          remarks: '${(vo['total'] as num?)?.toInt() ?? 0} 集',
        ),
      );
    }
    return items;
  }

  @override
  Future<SourceDetail> detail(String kind, String id) async {
    final parts = id.split(':');
    if (parts.length != 3 || parts[0] != 'xifan') {
      throw const SourceException('西饭剧集编号无效');
    }
    final result = await _get('/xifan/drama/getDuanjuInfo', {
      'source': parts[1],
      'duanjuId': parts[2],
    });
    final rawEpisodes = result['episodeList'];
    if (rawEpisodes is! List) {
      throw const SourceException('西饭没有返回分集');
    }
    final episodes = <SourceEpisode>[];
    for (final raw in rawEpisodes) {
      if (raw is! Map) continue;
      if (raw['unlock'] != true) continue;
      final url = _https(raw['playUrl']);
      if (url.isEmpty) continue;
      final index = (raw['index'] as num?)?.toInt() ?? episodes.length + 1;
      final title = _plain(raw['title']);
      episodes.add(
        SourceEpisode(
          name: title.isEmpty ? '第 $index 集' : title,
          url: url,
        ),
      );
    }
    if (episodes.isEmpty) {
      throw const SourceException('西饭当前没有可免费播放的分集');
    }
    return SourceDetail(
      id: id,
      title: _plain(result['title']),
      sourceId: source.id,
      cover: _https(result['coverImageUrl']),
      remarks: '${(result['total'] as num?)?.toInt() ?? episodes.length} 集',
      groups: [SourceGroup(name: '西饭', episodes: episodes)],
    );
  }
}

class _XifanGenre {
  const _XifanGenre({
    required this.id,
    required this.label,
    required this.version,
  });

  final int id;
  final String label;
  final int version;
}

String _plain(Object? value) =>
    (value == null ? '' : '$value').replaceAll(RegExp('<[^>]*>'), '').trim();

String _https(Object? value) {
  final raw = _plain(value);
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return '';
  }
  return uri.toString();
}
