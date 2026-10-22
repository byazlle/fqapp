import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fanqieduanwan/models/content_source.dart';
import 'package:fanqieduanwan/services/sources/hema_source_adapter.dart';
import 'package:fanqieduanwan/services/sources/xifan_source_adapter.dart';

void main() {
  final xifan = ContentSource(
    id: 'builtin:xifan',
    name: '西饭短剧',
    protocol: SourceProtocol.xifan,
    kinds: const {'video'},
    builtin: true,
    enabled: true,
  );
  final hema = ContentSource(
    id: 'builtin:hema',
    name: '河马短剧',
    protocol: SourceProtocol.hema,
    kinds: const {'video'},
    builtin: true,
    enabled: true,
  );

  http.Response json(Object value) =>
      http.Response.bytes(utf8.encode(jsonEncode(value)), 200);

  test('xifan browse/search/detail map onto the generic models', () async {
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/xifan/drama/portalPage') {
        final type = request.url.queryParameters['reqType'];
        if (type == 'duanjuCategory') {
          return json({
            'ret': 0,
            'result': {
              'elements': [
                {
                  'contents': [
                    {
                      'categoryItemVo': {
                        'categoryId': 7,
                        'oppoCategory': '都市',
                        'version': 1,
                        'subCategories': [
                          {'categoryId': 7, 'oppoCategory': '都市', 'version': 1},
                        ],
                      },
                    },
                  ],
                },
              ],
            },
          });
        }
        return json({
          'ret': 0,
          'result': {
            'elements': [
              {
                'contents': [
                  {
                    'duanjuVo': {
                      'source': 's1',
                      'duanjuId': 'd1',
                      'title': '西饭测试剧',
                      'coverImageUrl': 'https://img.example/a.jpg',
                      'total': 20,
                    },
                  },
                ],
              },
            ],
          },
        });
      }
      if (path == '/xifan/search/getSearchList') {
        return json({
          'ret': 0,
          'result': {
            'elements': [
              {
                'contents': [
                  {
                    'duanjuVo': {
                      'source': 's2',
                      'duanjuId': 'd2',
                      'title': '搜索结果',
                      'coverImageUrl': 'https://img.example/b.jpg',
                      'total': 8,
                    },
                  },
                ],
              },
            ],
          },
        });
      }
      if (path == '/xifan/drama/getDuanjuInfo') {
        return json({
          'ret': 0,
          'result': {
            'title': '西饭测试剧',
            'coverImageUrl': 'https://img.example/a.jpg',
            'total': 2,
            'episodeList': [
              {
                'episodeId': 'e1',
                'index': 1,
                'title': '第1集',
                'playUrl': 'https://v.example/1.m3u8',
                'unlock': true,
              },
              {
                'episodeId': 'e2',
                'index': 2,
                'title': '第2集',
                'playUrl': 'https://v.example/2.m3u8',
                'unlock': false,
              },
            ],
          },
        });
      }
      return http.Response('not found', 404);
    });

    final adapter = XifanSourceAdapter(xifan, client: client);
    final items = await adapter.browse('video');
    expect(items.single.id, 'xifan:s1:d1');
    expect(items.single.title, '西饭测试剧');
    expect(items.single.remarks, '20 集');

    final searched = await adapter.search('video', '测试');
    expect(searched.single.id, 'xifan:s2:d2');

    final detail = await adapter.detail('video', 'xifan:s1:d1');
    expect(detail.title, '西饭测试剧');
    // 锁定集被过滤，只保留可播放的第 1 集。
    expect(detail.groups.single.episodes.single.url, 'https://v.example/1.m3u8');
  });

  test('hema browse/search/detail parse __NEXT_DATA__ and free episodes', () async {
    String page(Map<String, Object?> props) =>
        '<html><script id="__NEXT_DATA__" type="application/json">'
        '${jsonEncode({'props': {'pageProps': props}})}'
        '</script></html>';

    final client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/browse' && request.method == 'GET') {
        return http.Response.bytes(
          utf8.encode(
            page({
              'bookList': [
                {
                  'bookId': 123,
                  'bookName': '河马测试剧',
                  'coverWap': 'https://img.example/h.jpg',
                  'totalChapterNum': 12,
                },
              ],
            }),
          ),
          200,
        );
      }
      if (path == '/seo/video/6007' && request.method == 'POST') {
        return json({
          'retCode': 0,
          'data': {
            'bookList': [
              {
                'bookId': 456,
                'bookName': '河马搜索',
                'coverWap': 'https://img.example/s.jpg',
                'totalChapterNum': 6,
              },
            ],
            'isMore': 0,
          },
        });
      }
      if (path == '/drama/123' && request.method == 'GET') {
        return http.Response.bytes(
          utf8.encode(
            page({
              'bookInfoVo': {
                'bookName': '河马测试剧',
                'coverWap': 'https://img.example/h.jpg',
              },
              'chapterList': [
                {
                  'chapterId': 1,
                  'chapterIndex': 1,
                  'chapterName': '第1集',
                  'isCharge': '0',
                  'chapterVideoVo': {'mp4720p': 'https://v.example/1.mp4'},
                },
                {
                  'chapterId': 2,
                  'chapterIndex': 2,
                  'chapterName': '第2集',
                  'isCharge': '1',
                  'chapterVideoVo': {'mp4720p': 'https://v.example/2.mp4'},
                },
              ],
            }),
          ),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final adapter = HemaSourceAdapter(hema, client: client);
    final items = await adapter.browse('video');
    expect(items.single.id, 'hema:123');
    expect(items.single.title, '河马测试剧');

    final searched = await adapter.search('video', '测试');
    expect(searched.single.id, 'hema:456');

    final detail = await adapter.detail('video', 'hema:123');
    expect(detail.title, '河马测试剧');
    expect(detail.groups.single.episodes.single.url, 'https://v.example/1.mp4');
    expect(detail.groups.single.episodes.single.name, '第1集');
  });
}
