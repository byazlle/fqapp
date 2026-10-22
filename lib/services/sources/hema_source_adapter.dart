import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/content_source.dart';
import '../../models/source_item.dart';
import 'source_adapter.dart';

/// 河马短剧适配器（接口形态取自 `jackotom/hongguo-drama` 的
/// `src/native/hema.js`）。
///
/// - 列表：`GET /browse`（HTML 里的 `__NEXT_DATA__`）
/// - 搜索：`POST /seo/video/6007`
/// - 详情：`GET /drama/<bookId>`（同样从 `__NEXT_DATA__` 取）
/// - 播放：`chapterVideoVo.mp4720p` / `mp4`，仅 `isCharge == '0'` 的免费集
class HemaSourceAdapter extends SourceAdapter {
  HemaSourceAdapter(this.source, {http.Client? client})
    : _client = client ?? http.Client();

  @override
  final ContentSource source;

  final http.Client _client;

  static const _base = 'https://www.kuaikaw.cn';
  static const _timeout = Duration(seconds: 10);
  static const _getHeaders = {
    'Accept': 'text/html',
    'User-Agent': 'Mozilla/5.0',
    'pname': 'www.kuaikaw.cn',
    'Origin': _base,
    'Referer': '$_base/',
  };
  static const _postHeaders = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'User-Agent': 'Mozilla/5.0',
    'pname': 'www.kuaikaw.cn',
    'Origin': _base,
    'Referer': '$_base/',
  };

  Future<String> _getText(String path) async {
    late final http.Response response;
    try {
      response = await _client
          .get(Uri.parse('$_base$path'), headers: _getHeaders)
          .timeout(_timeout);
    } catch (_) {
      throw const SourceException('河马连接失败或超时');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SourceException('河马 HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_base$path'),
            headers: _postHeaders,
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } catch (_) {
      throw const SourceException('河马连接失败或超时');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SourceException('河马 HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (decoded is! Map) throw const SourceException('河马返回数据异常');
    return Map<String, dynamic>.from(decoded);
  }

  Map<String, dynamic>? _nextData(String html) {
    final match = RegExp(
      r'''<script[^>]*id=["']__NEXT_DATA__["'][^>]*>([\s\S]*?)</script>''',
    ).firstMatch(html);
    if (match == null) return null;
    try {
      final decoded = jsonDecode(match.group(1)!);
      final props = decoded is Map ? decoded['props'] : null;
      final pageProps = props is Map ? props['pageProps'] : null;
      return pageProps is Map
          ? Map<String, dynamic>.from(pageProps)
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<SourceItem>> browse(
    String kind, {
    String? category,
    int page = 1,
  }) async {
    final path = page <= 1 ? '/browse' : '/browse/0/$page';
    final data = _nextData(await _getText(path));
    if (data == null) throw const SourceException('河马目录数据异常');
    return _items(data['bookList'], kind);
  }

  @override
  Future<List<SourceItem>> search(
    String kind,
    String query, {
    int page = 1,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const [];
    final response = await _postJson('/seo/video/6007', {
      'sourceType': 1,
      'keyword': keyword,
      'index': page,
    });
    if (response['retCode'] != 0 || response['data'] is! Map) {
      throw const SourceException('河马搜索数据异常');
    }
    final data = Map<String, dynamic>.from(response['data'] as Map);
    return _items(data['bookList'], kind);
  }

  List<SourceItem> _items(Object? raw, String kind) {
    if (raw is! List) return const [];
    final seen = <String>{};
    final items = <SourceItem>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final bookId = _plain(entry['bookId']);
      final title = _plain(entry['bookName']);
      if (bookId.isEmpty || title.isEmpty || !seen.add(bookId)) continue;
      items.add(
        SourceItem(
          id: 'hema:$bookId',
          title: title,
          sourceId: source.id,
          kind: kind,
          cover: _https(entry['coverWap']),
          remarks: '${(entry['totalChapterNum'] as num?)?.toInt() ?? 0} 集',
        ),
      );
    }
    return items;
  }

  @override
  Future<SourceDetail> detail(String kind, String id) async {
    final parts = id.split(':');
    if (parts.length != 2 || parts[0] != 'hema') {
      throw const SourceException('河马剧集编号无效');
    }
    final bookId = parts[1];
    final data = _nextData(await _getText('/drama/$bookId'));
    if (data == null) throw const SourceException('河马详情数据异常');
    final info = data['bookInfoVo'];
    final chapters = data['chapterList'];
    if (info is! Map || chapters is! List) {
      throw const SourceException('河马没有返回分集');
    }
    final episodes = <SourceEpisode>[];
    for (final raw in chapters) {
      if (raw is! Map) continue;
      if ('${raw['isCharge'] ?? ''}' != '0') continue;
      final video = raw['chapterVideoVo'];
      final url = video is Map
          ? (_https(video['mp4720p']).isNotEmpty
                ? _https(video['mp4720p'])
                : _https(video['mp4']))
          : '';
      if (url.isEmpty) continue;
      final index = (raw['chapterIndex'] as num?)?.toInt() ?? episodes.length + 1;
      final title = _plain(raw['chapterName']);
      episodes.add(
        SourceEpisode(
          name: title.isEmpty ? '第 $index 集' : title,
          url: url,
        ),
      );
    }
    if (episodes.isEmpty) {
      throw const SourceException('河马当前没有可免费播放的分集');
    }
    return SourceDetail(
      id: id,
      title: _plain(info['bookName']),
      sourceId: source.id,
      cover: _https(info['coverWap']),
      remarks: '${episodes.length} 集',
      groups: [SourceGroup(name: '河马', episodes: episodes)],
    );
  }
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
