import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanqieduanwan/models/content_source.dart';
import 'package:fanqieduanwan/models/source_blocklist.dart';
import 'package:fanqieduanwan/services/content_source_store.dart';
import 'package:fanqieduanwan/services/source_blocklist_service.dart';
import 'package:fanqieduanwan/services/sources/source_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ContentSourceStore.instance.resetForTest();
  });

  ContentSource custom(String url, {String id = 'custom:test'}) => ContentSource(
    id: id,
    name: '测试线路',
    protocol: SourceProtocol.cms,
    baseUrl: url,
    kinds: const {'video'},
  );

  group('SourceBlocklist.fromJson', () {
    test('parses sourceIds / hosts / message and normalizes case', () {
      final list = SourceBlocklist.fromJson({
        'sourceIds': ['Builtin:Xifan', ' builtin:hema '],
        'hosts': ['DEAD.example.com'],
        'message': '  线路维护中  ',
      });
      expect(list.sourceIds, {'builtin:xifan', 'builtin:hema'});
      expect(list.hosts, {'dead.example.com'});
      expect(list.message, '线路维护中');
    });

    test('accepts legacy blockedSourceIds / blockedHosts keys', () {
      final list = SourceBlocklist.fromJson({
        'blockedSourceIds': ['builtin:hema'],
        'blockedHosts': ['kuaikaw.cn'],
      });
      expect(list.sourceIds, {'builtin:hema'});
      expect(list.hosts, {'kuaikaw.cn'});
    });

    test('missing or malformed payload yields an empty list', () {
      expect(SourceBlocklist.fromJson(null).isEmpty, isTrue);
      expect(SourceBlocklist.fromJson('nope').isEmpty, isTrue);
      expect(SourceBlocklist.fromJson({'sourceIds': 'x'}).isEmpty, isTrue);
      expect(SourceBlocklist.fromJson({'hosts': [1, 2]}).isEmpty, isTrue);
    });
  });

  group('SourceBlocklist.blocks', () {
    test('matches by source id', () {
      final list = SourceBlocklist.fromJson({
        'sourceIds': ['builtin:xifan'],
      });
      expect(list.blocks(ContentSource.xifan), isTrue);
      expect(list.blocks(ContentSource.hema), isFalse);
      expect(list.blocks(ContentSource.fanqie), isFalse);
    });

    test('never blocks the built-in fanqie source even if listed', () {
      final list = SourceBlocklist.fromJson({
        'sourceIds': ['builtin:fanqie'],
      });
      expect(list.blocks(ContentSource.fanqie), isFalse);
    });

    test('matches host exactly and by subdomain, case-insensitive', () {
      final list = SourceBlocklist.fromJson({'hosts': ['Dead.Example.com']});
      expect(list.blocks(custom('https://dead.example.com/api.php/provide/vod/')), isTrue);
      expect(list.blocks(custom('https://api.dead.example.com/x/')), isTrue);
      expect(list.blocks(custom('https://notdead.example.com/')), isFalse);
      expect(list.blocks(custom('https://alive.example.com/')), isFalse);
    });

    test('sources without a base url are never blocked by host', () {
      final list = SourceBlocklist.fromJson({'hosts': ['example.com']});
      expect(list.blocks(ContentSource.xifan), isFalse);
    });

    test('blocksHost covers the same matching rules', () {
      final list = SourceBlocklist.fromJson({'hosts': ['example.com']});
      expect(list.blocksHost('https://cdn.example.com/a/'), isTrue);
      expect(list.blocksHost('https://other.com/a/'), isFalse);
      expect(list.blocksHost('not a url'), isFalse);
    });

    test('equality ignores key order and formatting', () {
      final a = SourceBlocklist.fromJson({'sourceIds': ['a', 'b'], 'hosts': ['h']});
      final b = SourceBlocklist.fromJson({'hosts': ['h'], 'sourceIds': ['b', 'a']});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(SourceBlocklist.fromJson({'sourceIds': ['a'], 'hosts': ['h']})),
      );
    });
  });

  group('ContentSourceStore + blocklist', () {
    test('blocked source drops out of forKind and activeFor falls back', () async {
      final store = ContentSourceStore.instance;
      await store.load();
      final source = await store.addCustom(name: '线路', url: 'https://a.example.com');
      await store.setEnabled(source!.id, true);
      await store.setActive('video', source.id);
      expect(store.activeFor('video').id, source.id);

      store.applyBlocklist(
        SourceBlocklist.fromJson({'sourceIds': [source.id]}),
      );
      expect(store.forKind('video').map((s) => s.id), [defaultSourceId]);
      expect(store.activeFor('video').id, defaultSourceId);
    });

    test('blocked host disables every custom source on it', () async {
      final store = ContentSourceStore.instance;
      await store.load();
      final a = await store.addCustom(name: 'A', url: 'https://a.example.com');
      final b = await store.addCustom(name: 'B', url: 'https://b.example.com');
      await store.setEnabled(a!.id, true);
      await store.setEnabled(b!.id, true);

      store.applyBlocklist(SourceBlocklist.fromJson({'hosts': ['example.com']}));
      // 两个自定义源同在 example.com 下，一起停用；番茄不受影响。
      expect(
        store.forKind('video').map((s) => s.id),
        [defaultSourceId],
      );
      expect(store.isBlocked(a), isTrue);
      expect(store.isBlocked(b), isTrue);
    });

    test('blocked source cannot be selected or enabled', () async {
      final store = ContentSourceStore.instance;
      await store.load();
      final source = await store.addCustom(name: '线路', url: 'https://a.example.com');
      await store.setEnabled(source!.id, true);
      await store.setActive('video', source.id);

      store.applyBlocklist(
        SourceBlocklist.fromJson({'sourceIds': [source.id]}),
      );
      await store.setActive('video', source.id);
      expect(store.activeFor('video').id, defaultSourceId);

      await store.setEnabled(source.id, false);
      await store.setEnabled(source.id, true);
      expect(store.sourceById(source.id)!.enabled, isFalse);
    });

    test('adding a custom source on a blocked host is rejected', () async {
      final store = ContentSourceStore.instance;
      await store.load();
      store.applyBlocklist(
        SourceBlocklist.fromJson({'hosts': ['example.com']}),
      );
      final source = await store.addCustom(name: '线路', url: 'https://x.example.com');
      expect(source, isNull);
    });

    test('probe on a blocked source reports unavailable without requesting', () async {
      final store = ContentSourceStore.instance;
      await store.load();
      final source = await store.addCustom(name: '线路', url: 'https://a.example.com');
      store.applyBlocklist(
        SourceBlocklist.fromJson({'sourceIds': [source!.id]}),
      );
      final probe = await store.probe(source);
      expect(probe.ok, isFalse);
      expect(probe.message, '该来源已停用');
    });

    test('blocking a built-in source (xifan) works end to end', () async {
      final store = ContentSourceStore.instance;
      await store.load();
      // 用户手动打开了西饭并设为当前源。
      await store.setEnabled('builtin:xifan', true);
      await store.setActive('video', 'builtin:xifan');
      expect(store.activeFor('video').id, 'builtin:xifan');

      // 远程名单把西饭停掉：当前选择回落番茄，且再也选不回来、打不开。
      store.applyBlocklist(
        SourceBlocklist.fromJson({'sourceIds': ['builtin:xifan']}),
      );
      expect(store.activeFor('video').id, defaultSourceId);
      await store.setActive('video', 'builtin:xifan');
      expect(store.activeFor('video').id, defaultSourceId);
      await store.setEnabled('builtin:xifan', false);
      await store.setEnabled('builtin:xifan', true);
      expect(store.sourceById('builtin:xifan')!.enabled, isFalse);
    });

    test('router refuses adapters for blocked sources', () async {
      final store = ContentSourceStore.instance;
      await store.load();
      await store.setEnabled('builtin:xifan', true);

      final router = SourceRouter();
      expect(router.adapterFor(store.sourceById('builtin:xifan')!), isNotNull);

      store.applyBlocklist(
        SourceBlocklist.fromJson({'sourceIds': ['builtin:xifan']}),
      );
      expect(router.adapterFor(store.sourceById('builtin:xifan')!), isNull);
      expect(
        store.fallbackChain('video').map((s) => s.id),
        isNot(contains('builtin:xifan')),
      );
    });
  });

  group('SourceBlocklistService', () {
    test('initialize applies the cached list when remote is unreachable', () async {
      SharedPreferences.setMockInitialValues({
        'source_blocklist.v1': jsonEncode({
          'sourceIds': ['builtin:xifan'],
          'hosts': [],
          'message': '缓存里的名单',
        }),
      });
      final store = ContentSourceStore.instance;
      await store.load();
      final service = SourceBlocklistService(
        client: MockClient((_) async => throw http.ClientException('offline')),
        store: store,
      );

      await service.initialize();

      expect(service.current.sourceIds, {'builtin:xifan'});
      expect(store.isBlocked(ContentSource.xifan), isTrue);
      expect(store.blocklistNotice, '缓存里的名单');
      expect(store.forKind('video').map((s) => s.id), [defaultSourceId]);
    });

    test('refresh applies the remote list and caches it', () async {
      final store = ContentSourceStore.instance;
      await store.load();
      Uri? requested;
      final service = SourceBlocklistService(
        client: MockClient((request) async {
          requested = request.url;
          // 用 bytes 返回：http.Response(String) 默认按 latin1 编码，
          // 中文 message 会抛异常（真实服务端返回的就是 UTF-8 字节）。
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'sourceIds': ['builtin:hema'],
                'hosts': ['kuaikaw.cn'],
                'message': '河马维护中',
              }),
            ),
            200,
          );
        }),
        store: store,
      );

      expect(await service.refresh(), isTrue);
      expect(requested.toString(), SourceBlocklistService.url);
      expect(store.isBlocked(ContentSource.hema), isTrue);
      expect(store.blocklistNotice, '河马维护中');

      // 已写入本地缓存：断网重启后继续生效。
      final sp = await SharedPreferences.getInstance();
      final cached = SourceBlocklist.fromJson(
        jsonDecode(sp.getString('source_blocklist.v1')!),
      );
      expect(cached.sourceIds, {'builtin:hema'});
      expect(cached.hosts, {'kuaikaw.cn'});
    });

    test('refresh keeps the current list on 404 or malformed payload', () async {
      final store = ContentSourceStore.instance;
      await store.load();
      store.applyBlocklist(
        SourceBlocklist.fromJson({'sourceIds': ['builtin:xifan']}),
      );
      var calls = 0;
      final service = SourceBlocklistService(
        client: MockClient((request) async {
          calls++;
          return calls == 1
              ? http.Response('404: Not Found', 404)
              : http.Response('<html>oops</html>', 200);
        }),
        store: store,
      );

      expect(await service.refresh(), isFalse); // 404
      expect(store.isBlocked(ContentSource.xifan), isTrue);
      // 200 但内容不是 JSON：解析失败同样保持现状。
      expect(await service.refresh(), isFalse);
      expect(calls, 2);
      expect(store.isBlocked(ContentSource.xifan), isTrue);
      // 服务侧从未成功拉取过名单，自己的视图保持为空；停用状态以 store 为准。
      expect(service.current.isEmpty, isTrue);
    });

    test('initialize with no cache and no network blocks nothing', () async {
      final store = ContentSourceStore.instance;
      await store.load();
      final service = SourceBlocklistService(
        client: MockClient((_) async => throw http.ClientException('offline')),
        store: store,
      );

      await service.initialize();

      expect(service.current.isEmpty, isTrue);
      expect(store.isBlocked(ContentSource.xifan), isFalse);
      // 番茄与已开启的自定义源照常可选。
      expect(store.activeFor('video').id, defaultSourceId);
    });
  });
}
