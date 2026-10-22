import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// 通用 CMS（苹果 CMS / TVBox 常用协议）客户端。
///
/// 协议形态来自 `jycao2/hongguoTV` 的 `docs/THIRD_SOURCES.md` 与
/// `jackotom/hongguo-drama` 的 `src/native/custom-source.js`：
/// - 列表：`?ac=list&t={分类}&pg={页}`
/// - 详情：`?ac=detail&ids={id}`
/// - 搜索：`?ac=detail&wd={关键词}`
/// - 播放：`vod_play_from` 以 `$$$` 分组、组内 `#` 分集、每集 `名称$地址`
///
/// 仅做协议解析，不携带任何内置源地址；地址由用户在设置里自行添加。
class CmsProbe {
  const CmsProbe({
    required this.ok,
    required this.message,
    required this.elapsedMs,
  });

  final bool ok;
  final String message;
  final int elapsedMs;
}

class CmsSeries {
  const CmsSeries({
    required this.id,
    required this.name,
    this.cover = '',
    this.remarks = '',
  });

  final String id;
  final String name;
  final String cover;
  final String remarks;
}

class CmsEpisode {
  const CmsEpisode({required this.name, required this.url});

  final String name;
  final String url;
}

class CmsPlayGroup {
  const CmsPlayGroup({required this.name, required this.episodes});

  final String name;
  final List<CmsEpisode> episodes;
}

class CmsDetail {
  const CmsDetail({
    required this.id,
    required this.name,
    this.cover = '',
    this.description = '',
    this.typeName = '',
    this.year = '',
    this.area = '',
    this.remarks = '',
    this.groups = const [],
  });

  final String id;
  final String name;
  final String cover;
  final String description;
  final String typeName;
  final String year;
  final String area;
  final String remarks;
  final List<CmsPlayGroup> groups;

  /// 优先选择 m3u8 组，其次第一条非空线路。
  CmsPlayGroup? get preferredGroup {
    for (final group in groups) {
      if (group.episodes.any((e) => e.url.contains('.m3u8'))) return group;
    }
    return groups.isEmpty ? null : groups.first;
  }
}

/// 把 `vod_play_from` / `vod_play_url` 拆成线路与分集。
///
/// 容错：空段跳过；没有 `$` 的整段当作地址；组数不一致时以较长的一侧为准。
List<CmsPlayGroup> parseCmsPlayGroups(String? from, String? url) {
  final names = (from ?? '').split(r'$$$');
  final urls = (url ?? '').split(r'$$$');
  final count = math.max(names.length, urls.length);
  final groups = <CmsPlayGroup>[];
  for (var i = 0; i < count; i++) {
    final rawName = i < names.length ? names[i].trim() : '';
    final rawUrls = i < urls.length ? urls[i] : '';
    final episodes = <CmsEpisode>[];
    for (final segment in rawUrls.split('#')) {
      final item = segment.trim();
      if (item.isEmpty) continue;
      final split = item.indexOf(r'$');
      if (split <= 0) {
        episodes.add(CmsEpisode(name: '第${episodes.length + 1}集', url: item));
        continue;
      }
      final name = item.substring(0, split).trim();
      final address = item.substring(split + 1).trim();
      if (address.isEmpty) continue;
      episodes.add(
        CmsEpisode(
          name: name.isEmpty ? '第${episodes.length + 1}集' : name,
          url: address,
        ),
      );
    }
    if (episodes.isEmpty) continue;
    groups.add(
      CmsPlayGroup(
        name: rawName.isEmpty ? '线路${groups.length + 1}' : rawName,
        episodes: episodes,
      ),
    );
  }
  return groups;
}

class CmsSourceClient {
  CmsSourceClient(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'Mozilla/5.0',
  };
  static const _timeout = Duration(seconds: 8);

  Uri _uri(Map<String, String> params) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      queryParameters: <String, String>{
        ...base.queryParameters,
        ...params,
      },
    );
  }

  Future<String?> _getText(Map<String, String> params) async {
    try {
      final response = await _client
          .get(_uri(params), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      // 现代 CMS 基本为 UTF-8；GBK 源需要额外的解码器，这里先不做猜测。
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _getJson(Map<String, String> params) async {
    final text = await _getText(params);
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// 探活：HTTP 2xx 且 JSON 里带 `list` 或 `class`。
  Future<CmsProbe> probe() async {
    final watch = Stopwatch()..start();
    final json = await _getJson({'ac': 'list', 'pg': '1'});
    watch.stop();
    if (json == null) {
      return CmsProbe(
        ok: false,
        message: '无法连接或返回的不是 JSON',
        elapsedMs: watch.elapsedMilliseconds,
      );
    }
    final ok = json['list'] is List || json['class'] is List;
    return CmsProbe(
      ok: ok,
      message: ok ? '连接正常' : '不是可识别的 CMS 接口（缺少 list/class）',
      elapsedMs: watch.elapsedMilliseconds,
    );
  }

  Future<List<CmsSeries>> list({String? category, int page = 1}) async {
    final json = await _getJson({
      'ac': 'list',
      if (category != null && category.isNotEmpty) 't': category,
      'pg': '$page',
    });
    return _parseSeries(json?['list']);
  }

  Future<List<CmsSeries>> search(String keyword, {int page = 1}) async {
    final json = await _getJson({
      'ac': 'detail',
      'wd': keyword,
      'pg': '$page',
    });
    return _parseSeries(json?['list']);
  }

  Future<CmsDetail?> detail(String id) async {
    final json = await _getJson({'ac': 'detail', 'ids': id});
    final list = json?['list'];
    if (list is! List || list.isEmpty) return null;
    final raw = list.first;
    if (raw is! Map) return null;
    final rawId = _text(raw['vod_id']);
    return CmsDetail(
      id: rawId.isEmpty ? id : rawId,
      name: _text(raw['vod_name']),
      cover: _text(raw['vod_pic']),
      description: _stripHtml(_text(raw['vod_content'])),
      typeName: _text(raw['vod_class']).isEmpty
          ? _text(raw['type_name'])
          : _text(raw['vod_class']),
      year: _text(raw['vod_year']),
      area: _text(raw['vod_area']),
      remarks: _text(raw['vod_remarks']),
      groups: parseCmsPlayGroups(
        _text(raw['vod_play_from']),
        _text(raw['vod_play_url']),
      ),
    );
  }

  List<CmsSeries> _parseSeries(Object? raw) {
    if (raw is! List) return const [];
    final items = <CmsSeries>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final id = _text(entry['vod_id']);
      final name = _text(entry['vod_name']);
      if (id.isEmpty || name.isEmpty) continue;
      items.add(
        CmsSeries(
          id: id,
          name: name,
          cover: _text(entry['vod_pic']),
          remarks: _text(entry['vod_remarks']),
        ),
      );
    }
    return items;
  }
}

String _text(Object? value) => value == null ? '' : '$value'.trim();

String _stripHtml(String value) =>
    value.replaceAll(RegExp('<[^>]*>'), '').trim();
