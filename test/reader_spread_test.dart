import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liuguang/models/media_item.dart';
import 'package:liuguang/pages/reader_page.dart';
import 'package:liuguang/services/chapter_text_formatter.dart';
import 'package:liuguang/services/reader_preferences.dart';
import 'package:liuguang/widgets/reader/reader_appearance_sheet.dart';
import 'package:liuguang/widgets/reader/reader_chapter_layout.dart';
import 'package:liuguang/widgets/reader/reader_paged_view.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'reader_page_mode': 'paged'});
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  group('pageColumns preference', () {
    test('round trips and clamps', () async {
      await ReaderPreferences(pageColumns: 2).save();
      final restored = await ReaderPreferences.load();
      expect(restored.pageColumns, 2);
      expect(ReaderPreferences(pageColumns: 9).normalized().pageColumns, 3);
      expect(ReaderPreferences(pageColumns: -2).normalized().pageColumns, 0);
      // copyWith keeps the value unless it is named explicitly.
      expect(ReaderPreferences(pageColumns: 3).copyWith().pageColumns, 3);
      expect(
        ReaderPreferences(pageColumns: 3).copyWith(pageColumns: 1).pageColumns,
        1,
      );
    });
  });

  group('multi-page spread', () {
    testWidgets('two pages share one item, left to right', (tester) async {
      final layout = _layout();
      final pages = <int>[];
      await _pumpReader(
        tester,
        size: const Size(1280, 800),
        layout: layout,
        spreadColumns: 2,
        onPageChanged: pages.add,
      );
      expect(
        find.byKey(const ValueKey('reader-text-page-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('reader-text-page-1')),
        findsOneWidget,
      );
      final left = tester.getRect(
        find.byKey(const ValueKey('reader-text-page-0')),
      );
      final right = tester.getRect(
        find.byKey(const ValueKey('reader-text-page-1')),
      );
      // Strict left-to-right order with the gap between them, never overlap.
      expect(left.right, lessThanOrEqualTo(right.left));
      expect(right.left - left.right, greaterThanOrEqualTo(23.9));
      expect(left.center.dx, lessThan(right.center.dx));
      // The next spread starts at the page after the pair.
      unawaited(
        tester
            .state<ReaderPagedViewState>(find.byType(ReaderPagedView))
            .turnPage(1),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(pages, [2]);
    });

    testWidgets('three pages share one item', (tester) async {
      // The layout viewport is one column's geometry; three columns plus the
      // two gaps must exactly fill the 1440 window: (1440 - 2*24) / 3 = 464.
      final layout = _layout(viewport: const Size(464, 900));
      final pages = <int>[];
      await _pumpReader(
        tester,
        size: const Size(1440, 900),
        layout: layout,
        spreadColumns: 3,
        onPageChanged: pages.add,
      );
      for (var page = 0; page < 3; page++) {
        expect(
          find.byKey(ValueKey('reader-text-page-$page')),
          findsOneWidget,
        );
      }
      final rects = [
        for (var page = 0; page < 3; page++)
          tester.getRect(find.byKey(ValueKey('reader-text-page-$page'))),
      ];
      expect(rects[0].right, lessThanOrEqualTo(rects[1].left));
      expect(rects[1].right, lessThanOrEqualTo(rects[2].left));
      unawaited(
        tester
            .state<ReaderPagedViewState>(find.byType(ReaderPagedView))
            .turnPage(1),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(pages, [3]);
    });

    testWidgets('a partial final spread keeps its pages in order', (
      tester,
    ) async {
      final layout = _layout();
      // Land on the last page: the final spread shows whatever remains, in
      // order, and never wraps around to page 0.
      final start = layout.pages.length - 1;
      await _pumpReader(
        tester,
        size: const Size(1280, 800),
        layout: layout,
        spreadColumns: 2,
        pageIndex: start,
      );
      expect(
        find.byKey(ValueKey('reader-text-page-$start')),
        findsOneWidget,
      );
      if (start % 2 == 1) {
        expect(
          find.byKey(ValueKey('reader-text-page-${start - 1}')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('reader-text-page-0')), findsNothing);
      }
    });

    testWidgets('turning past the last spread requests the chapter boundary', (
      tester,
    ) async {
      final layout = _layout();
      final boundary = Completer<void>();
      var requests = 0;
      await _pumpReader(
        tester,
        size: const Size(1280, 800),
        layout: layout,
        spreadColumns: 2,
        pageIndex: layout.pages.length - 1,
        onBoundary: (direction) {
          expect(direction, 1);
          requests++;
          return boundary.future;
        },
      );
      unawaited(
        tester
            .state<ReaderPagedViewState>(find.byType(ReaderPagedView))
            .turnPage(1),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(requests, 1);
      boundary.complete();
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('listening follow lands on the spread holding the position', (
      tester,
    ) async {
      final layout = _layout();
      final pages = <int>[];
      await _pumpReader(
        tester,
        size: const Size(1280, 800),
        layout: layout,
        spreadColumns: 2,
        onPageChanged: pages.add,
      );
      // 100% of the chapter is its last page, which lives in the last spread;
      // the host hears the spread's first page, not the page itself.
      final expectedPage =
          ((layout.pages.length - 1) ~/ 2) * 2;
      tester
          .state<ReaderPagedViewState>(find.byType(ReaderPagedView))
          .followProgress(1);
      await tester.pump(const Duration(milliseconds: 100));
      expect(pages, [expectedPage]);
    });

    testWidgets('one column stays a single centred page', (tester) async {
      final layout = _layout();
      await _pumpReader(
        tester,
        size: const Size(1280, 800),
        layout: layout,
        spreadColumns: 1,
      );
      expect(
        find.byKey(const ValueKey('reader-text-page-0')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('reader-text-page-1')), findsNothing);
      // Centred, not hugging the left edge of the wide window.
      final page = tester.getRect(
        find.byKey(const ValueKey('reader-text-page-0')),
      );
      expect(page.center.dx, closeTo(640, 1));
    });
  });

  group('window width drives the spread', () {
    testWidgets('a wide window with 三页 shows three pages', (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_page_mode': 'paged',
        'reader_page_columns': 3,
      });
      _setWindow(tester, const Size(1440, 900));
      await tester.pumpWidget(MaterialApp(home: _readerPage()));
      await tester.pumpAndSettle();
      for (var page = 0; page < 3; page++) {
        expect(
          find.byKey(ValueKey('reader-text-page-$page')),
          findsOneWidget,
        );
      }
    });

    testWidgets('a phone-width window collapses to one page', (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_page_mode': 'paged',
        'reader_page_columns': 3,
      });
      _setWindow(tester, const Size(400, 800));
      await tester.pumpWidget(MaterialApp(home: _readerPage()));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reader-text-page-0')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('reader-text-page-1')), findsNothing);
    });

    testWidgets('自动 gives two pages on a desktop window', (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_page_mode': 'paged',
        'reader_page_columns': 0,
      });
      _setWindow(tester, const Size(1280, 800));
      await tester.pumpWidget(MaterialApp(home: _readerPage()));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reader-text-page-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('reader-text-page-1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('reader-text-page-2')), findsNothing);
    });
  });

  group('appearance sheet', () {
    testWidgets('每屏页数 appears on wide windows and edits the preference', (
      tester,
    ) async {
      ReaderPreferences? changed;
      _setWindow(tester, const Size(1280, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderAppearanceSheet(
              initialValue: const ReaderPreferences(pageColumns: 1),
              onChanged: (value) => changed = value,
              onPickFont: () async => null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('每屏页数'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reader-page-columns-3')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(changed?.pageColumns, 3);
    });

    testWidgets('每屏页数 is hidden on phone-width windows', (tester) async {
      _setWindow(tester, const Size(400, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderAppearanceSheet(
              initialValue: const ReaderPreferences(),
              onChanged: (_) {},
              onPickFont: () async => null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('每屏页数'), findsNothing);
    });
  });
}

/// A chapter measured as one column. The spread only rearranges whole pages,
/// so a single-column layout is the input every case shares.
ReaderChapterLayout _layout({Size viewport = const Size(560, 620)}) =>
    ReaderChapterLayout(
      title: '第一章 测试',
      content: ChapterContent(
        blocks: [
          for (var i = 0; i < 40; i++)
            ChapterParagraph('清晨的风从窗边吹来，带着山间草木的清香。林舟推开木窗。'),
        ],
      ),
      spec: ReaderLayoutSpec(
        viewport: viewport,
        textScaler: TextScaler.noScaling,
        preferences: const ReaderPreferences(),
        fontFamily: null,
      ),
    );

ReaderPage _readerPage() => ReaderPage(
  bookId: 'spread-test',
  title: '测试书籍',
  chapters: [
    Chapter(itemId: 'c1', title: '第一章', volumeName: '正文'),
    Chapter(itemId: 'c2', title: '第二章', volumeName: '正文'),
  ],
  startIndex: 0,
  readerStore: MemoryReaderStore(),
  chapterCache: MemoryChapterCache(),
  chapterLoader: (chapter) async => List.generate(
    60,
    (index) => '第 $index 段。这是一段用于验证多页并排的测试正文。',
  ).join('\n\n'),
);

/// Resizes the test window. `setSurfaceSize` is deprecated in this Flutter
/// version and only reaches part of the view tree; `view.physicalSize`
/// applies to the view the widgets actually build against.
void _setWindow(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _pumpReader(
  WidgetTester tester, {
  required Size size,
  required ReaderChapterLayout layout,
  required int spreadColumns,
  ValueChanged<int>? onPageChanged,
  Future<void> Function(int)? onBoundary,
  int pageIndex = 0,
}) async {
  _setWindow(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReaderPagedView(
          layout: layout,
          pageIndex: pageIndex,
          hasPreviousChapter: false,
          hasNextChapter: true,
          onPageChanged: onPageChanged ?? (_) {},
          onBoundary: onBoundary ?? (direction) async {},
          onDragStart: () {},
          turnStyle: ReaderPageTurnStyle.none,
          backgroundColor: Colors.white,
          spreadColumns: spreadColumns,
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}
