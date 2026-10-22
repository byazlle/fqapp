import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fanqieduanwan/services/sources/cms_source_client.dart';

void main() {
  test('parses play groups split by \$\$\$, episodes by # and name by \$', () {
    final groups = parseCmsPlayGroups(
      r'liangzi$$$lzm3u8',
      r'第01集$https://a/1.m3u8#第02集$https://a/2.m3u8'
      r'$$$第01集$https://b/1.mp4',
    );
    expect(groups.length, 2);
    expect(groups.first.name, 'liangzi');
    expect(groups.first.episodes.length, 2);
    expect(groups.first.episodes.first.name, '第01集');
    expect(groups.first.episodes.first.url, 'https://a/1.m3u8');
    expect(groups[1].name, 'lzm3u8');
    expect(groups[1].episodes.single.url, 'https://b/1.mp4');
  });

  test('tolerates missing name separator and empty segments', () {
    final groups = parseCmsPlayGroups(
      '线路A',
      r'https://a/1.mp4##第02集$',
    );
    expect(groups, hasLength(1));
    expect(groups.single.episodes.length, 1);
    expect(groups.single.episodes.single.url, 'https://a/1.mp4');
  });

  test('cleans escaped slashes and HTML ampersands in play urls', () {
    final groups = parseCmsPlayGroups(
      '线路A',
      r'第1集$https:\/\/a.example.com\/1.m3u8?x=1&amp;y=2',
    );
    expect(
      groups.single.episodes.single.url,
      'https://a.example.com/1.m3u8?x=1&y=2',
    );
  });

  test('probe, list and detail parse against a CMS payload', () async {
    final client = MockClient((request) async {
      final ac = request.url.queryParameters['ac'];
      if (ac == 'list') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'class': [
                {'type_id': 1, 'type_name': '短剧'},
              ],
              'list': [
                {
                  'vod_id': 1001,
                  'vod_name': '测试短剧',
                  'vod_pic': 'https://img/cover.jpg',
                  'vod_remarks': '更新至 2 集',
                },
              ],
            }),
          ),
          200,
        );
      }
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'list': [
              {
                'vod_id': 1001,
                'vod_name': '测试短剧',
                'vod_pic': 'https://img/cover.jpg',
                'vod_content': '<p>简介正文</p>',
                'vod_play_from': '线路一\$\$\$线路二',
                'vod_play_url':
                    r'第01集$https://a/1.mp4#第02集$https://a/2.mp4'
                    r'$$$第01集$https://b/1.m3u8',
              },
            ],
          }),
        ),
        200,
      );
    });

    final cms = CmsSourceClient(
      'https://example.com/api.php/provide/vod/',
      client: client,
    );
    final probe = await cms.probe();
    expect(probe.ok, isTrue);

    final items = await cms.list();
    expect(items.single.id, '1001');
    expect(items.single.remarks, '更新至 2 集');

    final detail = await cms.detail('1001');
    expect(detail, isNotNull);
    expect(detail!.description, '简介正文');
    expect(detail.groups, hasLength(2));
    expect(detail.preferredGroup!.name, '线路二');
    expect(detail.preferredGroup!.episodes.single.url, 'https://b/1.m3u8');
  });

  test('probe fails clearly on a non-CMS JSON body', () async {
    final cms = CmsSourceClient(
      'https://example.com/api.php/provide/vod/',
      client: MockClient((_) async => http.Response('{"ok":true}', 200)),
    );
    final probe = await cms.probe();
    expect(probe.ok, isFalse);
    expect(probe.message, contains('list/class'));
  });
}
