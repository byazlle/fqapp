import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liuguang/models/chapter_media.dart';
import 'package:liuguang/models/media_item.dart';
import 'package:liuguang/pages/comic_reader_page.dart';
import 'package:liuguang/services/comic_reader_preferences.dart';
import 'package:liuguang/services/library_store.dart';

late ui.Image _portrait;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _portrait = await createTestImage(width: 100, height: 200, cache: false);
  });
  tearDownAll(() {
    _portrait.dispose();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({'comic_spread_pages': 2});
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  group('comic spread preference', () {
    test('spread pages round trips and clamps', () async {
      await ComicReaderPreferences(spreadPages: 3).save();
      final restored = await ComicReaderPreferences.load();
      expect(restored.spreadPages, 3);
      expect(ComicReaderPreferences(spreadPages: 9).normalized().spreadPages, 4);
      expect(ComicReaderPreferences(spreadPages: -1).normalized().spreadPages, 0);
      // copyWith keeps the value unless it is named explicitly.
      expect(ComicReaderPreferences(spreadPages: 2).copyWith().spreadPages, 2);
      expect(
        ComicReaderPreferences(spreadPages: 2).copyWith(spreadPages: 0).spreadPages,
        0,
      );
    });

    test('spreadForWidth follows the window and honours the preference', () {
      // 自动: phone stays single, desktop windows widen the spread.
      expect(ComicReaderPreferences.spreadForWidth(400), 1);
      expect(ComicReaderPreferences.spreadForWidth(800), 2);
      expect(ComicReaderPreferences.spreadForWidth(1280), 2);
      expect(ComicReaderPreferences.spreadForWidth(1320), 3);
      expect(ComicReaderPreferences.spreadForWidth(1600), 3);
      expect(ComicReaderPreferences.spreadForWidth(1880), 4);
      expect(ComicReaderPreferences.spreadForWidth(2600), 4);
      // A fixed choice is still capped by the width: a 340px column is the
      // narrowest readable comic page.
      expect(ComicReaderPreferences.spreadForWidth(800, preferred: 4), 2);
      expect(ComicReaderPreferences.spreadForWidth(1000, preferred: 3), 2);
      expect(ComicReaderPreferences.spreadForWidth(2400, preferred: 1), 1);
      // Degenerate widths never produce zero columns.
      expect(ComicReaderPreferences.spreadForWidth(0), 1);
      expect(ComicReaderPreferences.spreadForWidth(double.nan), 1);
    });
  });

  group('comic paged spread', () {
    testWidgets('翻页模式并排显示两页，从左到右保序', (tester) async {
      await _openPagedReader(tester, size: const Size(1280, 800));
      expect(
        find.byKey(const ValueKey('comic-image-1-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('comic-image-1-1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('comic-image-1-2')), findsNothing);
      final left = tester.getRect(
        find.byKey(const ValueKey('comic-image-1-0')),
      );
      final right = tester.getRect(
        find.byKey(const ValueKey('comic-image-1-1')),
      );
      // Strict left-to-right order with the gap between them, never overlap.
      expect(left.right, lessThanOrEqualTo(right.left));
      expect(right.left - left.right, greaterThanOrEqualTo(15.9));
      expect(left.center.dx, lessThan(right.center.dx));
      // Page numbers on the tiles keep the true reading order.
      expect(find.text('第 1 / 6 页'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _leave(tester);
    });

    testWidgets('翻到下一屏顺序正确并记录进度', (tester) async {
      final store = _ComicStore();
      await _openPagedReader(tester, size: const Size(1280, 800), store: store);
      await tester.drag(
        find.byKey(const ValueKey('comic-reader-paged-view')),
        const Offset(-900, 0),
      );
      await tester.pumpAndSettle();
      // The spread's first page is the position the reader reports.
      expect(find.text('第 3 / 6 页'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('comic-image-1-2')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(store.records['manga:comic-test']!['position'], closeTo(2.0, .001));
      expect(tester.takeException(), isNull);
      await _leave(tester);
    });

    testWidgets('三页并排且顺序正确', (tester) async {
      SharedPreferences.setMockInitialValues({'comic_spread_pages': 3});
      await _openPagedReader(tester, size: const Size(1440, 900), count: 7);
      for (var page = 0; page < 3; page++) {
        expect(
          find.byKey(ValueKey('comic-image-1-$page')),
          findsOneWidget,
        );
      }
      expect(find.byKey(const ValueKey('comic-image-1-3')), findsNothing);
      final rects = [
        for (var page = 0; page < 3; page++)
          tester.getRect(find.byKey(ValueKey('comic-image-1-$page'))),
      ];
      expect(rects[0].right, lessThanOrEqualTo(rects[1].left));
      expect(rects[1].right, lessThanOrEqualTo(rects[2].left));
      await _leave(tester);
    });

    testWidgets('残缺的最后一屏只显示剩余页，不回到第一页', (tester) async {
      SharedPreferences.setMockInitialValues({'comic_spread_pages': 3});
      await _openPagedReader(tester, size: const Size(1440, 900), count: 7);
      final view = find.byKey(const ValueKey('comic-reader-paged-view'));
      await tester.drag(view, const Offset(-1000, 0));
      await tester.pumpAndSettle();
      await tester.drag(view, const Offset(-1000, 0));
      await tester.pumpAndSettle();
      expect(find.text('第 7 / 7 页'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('comic-image-1-6')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('comic-image-1-0')), findsNothing);
      expect(find.byKey(const ValueKey('comic-image-1-5')), findsNothing);
      await _leave(tester);
    });

    testWidgets('四页偏好在窄窗被宽度上限收敛为两页', (tester) async {
      SharedPreferences.setMockInitialValues({'comic_spread_pages': 4});
      await _openPagedReader(tester, size: const Size(1000, 800));
      expect(
        find.byKey(const ValueKey('comic-image-1-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('comic-image-1-1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('comic-image-1-2')), findsNothing);
      await _leave(tester);
    });

    testWidgets('自动档按窗口宽度选择页数', (tester) async {
      SharedPreferences.setMockInitialValues({'comic_spread_pages': 0});
      await _openPagedReader(tester, size: const Size(1600, 900));
      for (var page = 0; page < 3; page++) {
        expect(
          find.byKey(ValueKey('comic-image-1-$page')),
          findsOneWidget,
        );
      }
      expect(find.byKey(const ValueKey('comic-image-1-3')), findsNothing);
      await _leave(tester);
    });

    testWidgets('手机宽度永远单页', (tester) async {
      SharedPreferences.setMockInitialValues({'comic_spread_pages': 3});
      await _openPagedReader(tester, size: const Size(400, 800));
      expect(
        find.byKey(const ValueKey('comic-image-1-0')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('comic-image-1-1')), findsNothing);
      await _leave(tester);
    });

    testWidgets('恢复的页码落在承载它的那一屏', (tester) async {
      final store = _ComicStore()
        ..records['manga:comic-test'] = _saved(position: 4.0);
      await _openPagedReader(tester, size: const Size(1280, 800), store: store);
      expect(find.text('第 5 / 6 页'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('comic-image-1-4')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('comic-image-1-5')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('comic-image-1-0')), findsNothing);
      await _leave(tester);
    });

    testWidgets('窗口缩放后仍停留在承载当前页的那一屏', (tester) async {
      await _openPagedReader(tester, size: const Size(1280, 800));
      final view = find.byKey(const ValueKey('comic-reader-paged-view'));
      await tester.drag(view, const Offset(-900, 0));
      await tester.pumpAndSettle();
      expect(find.text('第 3 / 6 页'), findsOneWidget);
      // Widening to 1920 switches 自动 to four pages; page 2 still opens the
      // first spread instead of the view snapping back to page 0.
      tester.view.physicalSize = const Size(1920, 1080);
      await tester.pumpAndSettle();
      expect(find.text('第 3 / 6 页'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('comic-image-1-2')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _leave(tester);
    });

    testWidgets('每屏页数选择器切换并持久化', (tester) async {
      SharedPreferences.setMockInitialValues({'comic_spread_pages': 1});
      _setWindow(tester, const Size(1280, 800));
      await tester.pumpWidget(
        _app(store: _ComicStore(), provider: _providerFor(_portrait)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('切换为翻页模式'));
      await tester.pumpAndSettle();
      // One page per screen before the switch.
      expect(find.byKey(const ValueKey('comic-image-1-1')), findsNothing);
      await tester.tap(find.byTooltip('每屏页数'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('三页'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('comic-image-1-2')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('comic-image-1-3')), findsNothing);
      final restored = await ComicReaderPreferences.load();
      expect(restored.spreadPages, 3);
      expect(tester.takeException(), isNull);
      await _leave(tester);
    });
  });
}

final _chapters = [
  Chapter(itemId: 'chapter-1', title: '第一章', volumeName: ''),
  Chapter(itemId: 'chapter-2', title: '第二章', volumeName: ''),
  Chapter(itemId: 'chapter-3', title: '第三章', volumeName: ''),
];

List<ComicImage> _images(Chapter chapter, {int count = 6}) => List.generate(
  count,
  (index) => ComicImage(
    url: 'https://images.test/${chapter.itemId}/$index.png',
    width: 100,
    height: 200,
  ),
);

Map<String, dynamic> _saved({String chapterId = 'chapter-1', double position = 0}) => {
  'id': 'manga:comic-test',
  'contentId': 'comic-test',
  'kind': 'manga',
  'chapterId': chapterId,
  'episode': chapterId == 'chapter-1' ? 0 : 1,
  'position': position,
  'maxScroll': 6.0,
  'positionUnit': 'comic-page',
  'progress': .25,
  'title': '漫画',
};

ComicImageProviderFactory _providerFor(ui.Image image) {
  final providers = <String, ImageProvider<Object>>{};
  return (comic) => providers.putIfAbsent(
    comic.url,
    () => _TestImageProvider(Future.value(image)),
  );
}

/// Resizes the test window the way the reader spread tests do.
void _setWindow(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _openPagedReader(
  WidgetTester tester, {
  required Size size,
  ReaderStore? store,
  int count = 6,
}) async {
  _setWindow(tester, size);
  await tester.pumpWidget(
    _app(
      store: store ?? _ComicStore(),
      loader: (chapter) async => _images(chapter, count: count),
      provider: _providerFor(_portrait),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('切换为翻页模式'));
  await tester.pumpAndSettle();
}

Widget _app({
  required ReaderStore store,
  required ComicImageProviderFactory provider,
  ComicChapterLoader? loader,
  int count = 6,
}) => MaterialApp(
  home: ComicReaderPage(
    bookId: 'comic-test',
    title: '漫画',
    chapters: _chapters,
    startIndex: 0,
    readerStore: store,
    chapterLoader: loader ?? (chapter) async => _images(chapter, count: count),
    imageProviderFactory: provider,
  ),
);

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

class _TestImageProvider extends ImageProvider<_TestImageProvider> {
  final Future<ui.Image> future;
  _TestImageProvider(this.future);

  @override
  Future<_TestImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _TestImageProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    future.then((image) => ImageInfo(image: image.clone())),
  );
}

class _ComicStore implements ReaderStore {
  final records = <String, Map<String, dynamic>>{};
  Future<void>? writeDelay;
  bool failWrites = false;

  @override
  Future<Map<String, dynamic>?> historyEntry(String id) async =>
      records[id] == null ? null : Map.of(records[id]!);

  @override
  Future<void> addHistory(Map<String, dynamic> entry) async {
    final copy = Map<String, dynamic>.from(entry);
    await writeDelay;
    if (failWrites) throw StateError('storage unavailable');
    records[copy['id'] as String] = copy;
  }

  @override
  Future<void> updateProgress(
    String id,
    int episode,
    double progress, {
    String? chapterId,
    double? position,
    double? maxScroll,
  }) async {
    await writeDelay;
    if (failWrites) throw StateError('storage unavailable');
    if (records[id] case final entry?) {
      records[id] = {
        ...entry,
        'episode': episode,
        'progress': progress,
        'chapterId': ?chapterId,
        'position': ?position,
        'maxScroll': ?maxScroll,
      };
    }
  }

  @override
  Future<void> accumulateReadTime(
    String bookId,
    String kind,
    double seconds, {
    DateTime? at,
  }) async {}
  @override
  Future<Set<String>> watchedEpisodeIds(String id) async => <String>{};

  @override
  Future<void> markEpisodeWatched(String id, Iterable<String> episodeIds) async {}

  @override
  Future<void> forgetWatchedEpisodes(String id) async {}
}
