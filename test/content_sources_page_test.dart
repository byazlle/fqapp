import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fanqieduanwan/pages/content_sources_page.dart';
import 'package:fanqieduanwan/services/content_source_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ContentSourceStore.instance.resetForTest();
  });

  testWidgets('lists compatible sources and switches per kind', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ContentSourcesPage()));
    await tester.pumpAndSettle();

    // 短剧：番茄 + 三个默认关闭的第三方源都可见，方便用户按需开启。
    expect(find.text('番茄（内置）'), findsOneWidget);
    expect(find.text('红果短剧（网页版）'), findsOneWidget);
    expect(find.text('西饭短剧'), findsOneWidget);
    expect(find.text('河马短剧'), findsOneWidget);
    expect(find.text('自动容错'), findsOneWidget);

    // 小说：第三方视频源不声明支持该类型，只剩番茄。
    await tester.tap(find.byKey(const ValueKey('source_kind_book')));
    await tester.pumpAndSettle();
    expect(find.text('番茄（内置）'), findsOneWidget);
    expect(find.text('红果短剧（网页版）'), findsNothing);

    // 小说分类不允许添加视频 CMS 源。
    final addButton = tester.widget<FilledButton>(
      find.byKey(const Key('add_custom_source')),
    );
    expect(addButton.onPressed, isNull);

    // 回到短剧可添加自定义源，并打开对话框。
    await tester.tap(find.byKey(const ValueKey('source_kind_video')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('add_custom_source')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_custom_source')));
    await tester.pumpAndSettle();
    expect(find.text('添加 CMS 源'), findsOneWidget);
    expect(find.byKey(const Key('custom_source_url')), findsOneWidget);
  });
}
