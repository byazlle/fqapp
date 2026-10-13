import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/imported_book_store.dart';

void main() {
  group('parseImportedBookBytes', () {
    test('按常见中文章节标题切分 TXT 并保留章节正文', () {
      final parsed = parseImportedBookBytes(
        fileName: '故事.txt',
        bytes: Uint8List.fromList(
          utf8.encode('第一章 开始\n清晨醒来。\n\n第二章 出发\n走向远方。'),
        ),
      );

      expect(parsed.title, '故事');
      expect(parsed.format, 'txt');
      expect(parsed.chapters.map((chapter) => chapter.title), [
        '第一章 开始',
        '第二章 出发',
      ]);
      expect(parsed.chapters.first.text, contains('清晨醒来'));
      expect(parsed.chapters.last.text, contains('走向远方'));
    });

    test('没有章节标题时把 TXT 作为单章导入', () {
      final parsed = parseImportedBookBytes(
        fileName: '散文.TXT',
        bytes: Uint8List.fromList(utf8.encode('第一段\n\n第二段')),
      );

      expect(parsed.title, '散文');
      expect(parsed.chapters, hasLength(1));
      expect(parsed.chapters.single.text, contains('第二段'));
    });

    test('按 EPUB spine 顺序提取章节标题、作者与正文', () {
      final archive = Archive()
        ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
        ..addFile(
          ArchiveFile.string(
            'META-INF/container.xml',
            '''<?xml version="1.0"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>
</container>''',
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'OEBPS/content.opf',
            '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <metadata><dc:title>EPUB 书名</dc:title><dc:creator>作者甲</dc:creator></metadata>
  <manifest><item id="one" href="Text/one.xhtml" media-type="application/xhtml+xml"/>
    <item id="two" href="Text/two.xhtml" media-type="application/xhtml+xml"/></manifest>
  <spine><itemref idref="two"/><itemref idref="one"/></spine>
</package>''',
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'OEBPS/Text/one.xhtml',
            '<html><body><h1>第一章</h1><p>正文一。</p></body></html>',
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'OEBPS/Text/two.xhtml',
            '<html><body><h1>序章</h1><p>正文二。</p></body></html>',
          ),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final parsed = parseImportedBookBytes(fileName: 'fallback.epub', bytes: bytes);

      expect(parsed.title, 'EPUB 书名');
      expect(parsed.author, '作者甲');
      expect(parsed.chapters.map((chapter) => chapter.title), ['序章', '第一章']);
      expect(parsed.chapters.first.text, contains('正文二'));
    });

    test('拒绝不支持的格式与空正文', () {
      expect(
        () => parseImportedBookBytes(
          fileName: 'book.pdf',
          bytes: Uint8List.fromList([1]),
        ),
        throwsFormatException,
      );
      expect(
        () => parseImportedBookBytes(
          fileName: 'empty.txt',
          bytes: Uint8List.fromList(utf8.encode('  ')),
        ),
        throwsFormatException,
      );
    });
  });

  group('ImportedBookStore', () {
    late Directory directory;
    late ImportedBookStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('fqapp-import-test-');
      store = ImportedBookStore(rootDirectoryProvider: () async => directory);
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('写入私有章节文件后仍可恢复书籍目录与正文', () async {
      final imported = await store.importBytes(
        fileName: '持久化.txt',
        bytes: Uint8List.fromList(utf8.encode('第一章\n保存在本地。')),
      );

      final loaded = await store.book(imported.id);
      expect(loaded?.title, '持久化');
      expect(loaded?.chapters, hasLength(1));
      expect(
        await store.chapterText(imported.id, imported.chapters.single.itemId),
        contains('保存在本地'),
      );
      expect((await store.books()).map((book) => book.id), [imported.id]);
    });
  });
}
