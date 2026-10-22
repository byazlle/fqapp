import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanqieduanwan/models/content_source.dart';
import 'package:fanqieduanwan/services/content_source_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ContentSourceStore.instance.resetForTest();
  });

  test('defaults to the built-in fanqie source for every kind', () async {
    final store = ContentSourceStore.instance;
    await store.load();

    for (final kind in contentKindLabels.keys) {
      expect(store.activeFor(kind).id, defaultSourceId);
    }
    // 第三方源默认关闭，只有番茄参与默认切换。
    expect(store.forKind('video'), hasLength(1));
    expect(store.autoFallback, isTrue);
  });

  test('custom CMS source supports video/manju and is selected per kind', () async {
    final store = ContentSourceStore.instance;
    await store.load();

    final source = await store.addCustom(
      name: '我的线路 A',
      url: 'https://example.com',
    );
    expect(source, isNotNull);
    expect(
      source!.baseUrl,
      'https://example.com/api.php/provide/vod/',
    );
    await store.setEnabled(source.id, true);

    await store.setActive('video', source.id);
    expect(store.activeFor('video').id, source.id);
    // 其它类型独立：追剧不影响漫剧、小说与听书。
    expect(store.activeFor('manju').id, defaultSourceId);
    expect(store.activeFor('book').id, defaultSourceId);
    expect(store.activeFor('audio').id, defaultSourceId);
    expect(store.forKind('book').map((s) => s.id), [defaultSourceId]);
  });

  test('selection survives a reload', () async {
    final store = ContentSourceStore.instance;
    await store.load();
    final source = await store.addCustom(
      name: '线路 B',
      url: 'https://b.example.com/api.php/provide/vod/',
    );
    await store.setEnabled(source!.id, true);
    await store.setActive('video', source.id);

    // 模拟重启：清掉内存态后重新从 SharedPreferences 读。
    store.resetForTest();
    await store.load();
    expect(store.activeFor('video').id, source.id);
    expect(store.sourceById(source.id)?.name, '线路 B');
  });

  test('disabling the active source falls back to fanqie', () async {
    final store = ContentSourceStore.instance;
    await store.load();
    final source = await store.addCustom(
      name: '线路 C',
      url: 'https://c.example.com/api.php/provide/vod/',
    );
    await store.setEnabled(source!.id, true);
    await store.setActive('video', source.id);

    await store.setEnabled(source.id, false);
    expect(store.activeFor('video').id, defaultSourceId);
    expect(store.forKind('video').map((s) => s.id), [defaultSourceId]);
  });

  test('rejects invalid or duplicate custom sources', () async {
    final store = ContentSourceStore.instance;
    await store.load();

    expect(await store.addCustom(name: ' ', url: 'https://x.com'), isNull);
    expect(await store.addCustom(name: 'A', url: 'ftp://x.com'), isNull);
    expect(await store.addCustom(name: 'A', url: 'https://x.com'), isNotNull);
    expect(await store.addCustom(name: 'A2', url: 'https://x.com'), isNull);
  });

  test('built-in third-party sources are disabled until enabled', () async {
    final store = ContentSourceStore.instance;
    await store.load();
    final hongguo = store.sourceById('builtin:hongguo')!;
    expect(hongguo.enabled, isFalse);
    expect(hongguo.supports('novel'), isFalse);

    await store.setEnabled(hongguo.id, true);
    await store.setActive('manju', hongguo.id);
    expect(store.activeFor('manju').id, hongguo.id);
    expect(store.activeFor('video').id, defaultSourceId);
  });
}
