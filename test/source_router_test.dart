import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanqieduanwan/models/content_source.dart';
import 'package:fanqieduanwan/models/source_item.dart';
import 'package:fanqieduanwan/pages/source_browse_page.dart';
import 'package:fanqieduanwan/services/content_source_store.dart';
import 'package:fanqieduanwan/services/sources/source_adapter.dart';

class _FakeAdapter extends SourceAdapter {
  _FakeAdapter(this.source, {this.fail = false});

  @override
  final ContentSource source;
  final bool fail;

  @override
  Future<List<SourceItem>> browse(
    String kind, {
    String? category,
    int page = 1,
  }) async {
    if (fail) throw const SourceException('upstream down');
    return [
      SourceItem(
        id: '1',
        title: '来自 ${source.name}',
        sourceId: source.id,
        kind: kind,
      ),
    ];
  }

  @override
  Future<List<SourceItem>> search(
    String kind,
    String query, {
    int page = 1,
  }) => browse(kind, page: page);

  @override
  Future<SourceDetail> detail(String kind, String id) async => SourceDetail(
    id: id,
    title: '详情 ${source.name}',
    sourceId: source.id,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ContentSourceStore.instance.resetForTest();
  });

  Future<({ContentSource a, ContentSource b})> setupSources() async {
    final store = ContentSourceStore.instance;
    await store.load();
    final a = await store.addCustom(name: 'A', url: 'https://a.example.com');
    final b = await store.addCustom(name: 'B', url: 'https://b.example.com');
    await store.setEnabled(a!.id, true);
    await store.setEnabled(b!.id, true);
    await store.setActive('video', a.id);
    return (a: a, b: b);
  }

  test('falls back to the next enabled source when the active one fails', () async {
    final sources = await setupSources();
    final store = ContentSourceStore.instance;
    final router = SourceRouter(
      store: store,
      adapterFactory: (source) => source.protocol == SourceProtocol.fanqie
          ? null
          : _FakeAdapter(source, fail: source.id == sources.a.id),
    );

    final result = await router.browse('video');
    expect(result.source.id, sources.b.id);
    expect(result.fellBack, isTrue);
    expect(result.value.single.title, '来自 B');
  });

  test('does not fall back when auto fallback is off', () async {
    final sources = await setupSources();
    final store = ContentSourceStore.instance;
    await store.setAutoFallback(false);
    final router = SourceRouter(
      store: store,
      adapterFactory: (source) => source.protocol == SourceProtocol.fanqie
          ? null
          : _FakeAdapter(source, fail: source.id == sources.a.id),
    );

    await expectLater(
      router.browse('video'),
      throwsA(isA<SourceException>()),
    );
  });

  test('sources without a real adapter fail with a clear message', () async {
    final store = ContentSourceStore.instance;
    await store.load();
    await store.setEnabled('builtin:hongguo', true);
    await store.setActive('manju', 'builtin:hongguo');
    await store.setAutoFallback(false);
    final router = SourceRouter(store: store);

    await expectLater(
      router.browse('manju'),
      throwsA(
        predicate<SourceException>(
          (error) => error.message.contains('适配器尚未接入'),
        ),
      ),
    );
  });

  testWidgets('browse page renders router results and opens detail', (tester) async {
    final sources = await setupSources();
    final router = SourceRouter(
      store: ContentSourceStore.instance,
      adapterFactory: (source) => source.protocol == SourceProtocol.fanqie
          ? null
          : _FakeAdapter(source),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SourceBrowsePage(
          source: sources.a,
          kind: 'video',
          router: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('来自 A'), findsOneWidget);
    await tester.tap(find.text('来自 A'));
    await tester.pumpAndSettle();
    expect(find.text('详情 A'), findsOneWidget);
    expect(find.text('这个来源没有提供可播放的分集地址。'), findsOneWidget);
  });
}
