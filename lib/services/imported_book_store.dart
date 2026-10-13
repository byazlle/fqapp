import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import '../models/media_item.dart';

const _maxBookFileBytes = 32 * 1024 * 1024;
const _maxExpandedEpubBytes = 64 * 1024 * 1024;
const _maxEpubEntries = 4000;
const _maxImportedChapters = 20000;
const _bookIdPattern = r'^local_[0-9]+_[a-f0-9]+$';

/// An imported book and its ordered local chapter catalogue.
class ImportedBook {
  final String id;
  final String title;
  final String author;
  final String format;
  final DateTime addedAt;
  final List<Chapter> chapters;
  final List<String> _chapterFiles;

  ImportedBook._({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.addedAt,
    required List<Chapter> chapters,
    required List<String> chapterFiles,
  }) : chapters = List.unmodifiable(chapters),
       _chapterFiles = List.unmodifiable(chapterFiles);

  MediaItem toMediaItem() => MediaItem(
    id: id,
    title: title,
    cover: '',
    author: author,
    badge: '本地',
    ep: chapters.length.toString(),
    kind: 'book',
  );

  Map<String, dynamic> _toManifest() => {
    'id': id,
    'title': title,
    'author': author,
    'format': format,
    'addedAt': addedAt.millisecondsSinceEpoch,
    'chapters': [
      for (var index = 0; index < chapters.length; index++)
        {
          'id': chapters[index].itemId,
          'title': chapters[index].title,
          'file': _chapterFiles[index],
        },
    ],
  };
}

/// One parsed chapter before it is stored in the app-private directory.
@immutable
class ParsedBookChapter {
  final String title;
  final String text;
  const ParsedBookChapter({required this.title, required this.text});
}

/// Parsed book data, independent of Flutter and filesystem state.
@immutable
class ParsedImportedBook {
  final String title;
  final String author;
  final String format;
  final List<ParsedBookChapter> chapters;

  ParsedImportedBook({
    required this.title,
    required this.author,
    required this.format,
    required List<ParsedBookChapter> chapters,
  }) : chapters = List.unmodifiable(chapters);
}

/// Local imported-book persistence. Book text is stored as private chapter
/// files; the source document is not retained and is never uploaded.
class ImportedBookStore {
  ImportedBookStore({Future<Directory> Function()? rootDirectoryProvider})
    : _rootDirectoryProvider =
          rootDirectoryProvider ?? getApplicationSupportDirectory;

  static final ImportedBookStore instance = ImportedBookStore();
  static const _picker = MethodChannel('fqapp/local_books');
  static bool isLocalBookId(String id) => RegExp(_bookIdPattern).hasMatch(id);

  final Future<Directory> Function() _rootDirectoryProvider;
  Future<Directory>? _rootFuture;
  static final _random = Random.secure();

  Future<Directory> _root() => _rootFuture ??= _createRoot();

  Future<ImportedBook?> pickAndImport() async {
    final selected = await _picker.invokeMapMethod<Object?, Object?>(
      'pickBookFile',
    );
    if (selected == null) return null;
    final fileName = selected['name']?.toString() ?? '';
    final decodedText = selected['text'] is String
        ? selected['text'] as String
        : null;
    final sourceByteLength = selected['byteLength'] is int
        ? selected['byteLength'] as int
        : null;
    final rawBytes = selected['bytes'];
    final bytes = rawBytes is Uint8List
        ? rawBytes
        : rawBytes is List<int>
        ? Uint8List.fromList(rawBytes)
        : null;
    final isTxt = fileName.toLowerCase().endsWith('.txt');
    if (fileName.isEmpty ||
        (isTxt && (decodedText == null || sourceByteLength == null)) ||
        (!isTxt && bytes == null)) {
      throw const FormatException('无法读取所选文件');
    }
    return importBytes(
      fileName: fileName,
      bytes: bytes ?? Uint8List(0),
      decodedText: decodedText,
      sourceByteLength: sourceByteLength,
    );
  }

  Future<Directory> _createRoot() async {
    final support = await _rootDirectoryProvider();
    final root = Directory(
      '${support.path}${Platform.pathSeparator}imported_books',
    );
    await root.create(recursive: true);
    return root;
  }

  /// Parses a chosen TXT or EPUB in a worker isolate and persists its chapters.
  Future<ImportedBook> importBytes({
    required String fileName,
    required Uint8List bytes,
    String? decodedText,
    int? sourceByteLength,
  }) async {
    if (bytes.isEmpty && decodedText == null) {
      throw const FormatException('文件内容为空');
    }
    final byteLength = sourceByteLength ?? bytes.lengthInBytes;
    if (byteLength < 0) throw const FormatException('文件长度无效');
    if (byteLength > _maxBookFileBytes) {
      throw const FormatException('请选择小于 32 MB 的 TXT 或 EPUB 文件');
    }
    final parsedData = await Isolate.run<Map<String, Object?>>(() {
      final parsed = parseImportedBookBytes(
        fileName: fileName,
        bytes: bytes,
        decodedText: decodedText,
      );
      return {
        'title': parsed.title,
        'author': parsed.author,
        'format': parsed.format,
        'chapters': [
          for (final chapter in parsed.chapters)
            {'title': chapter.title, 'text': chapter.text},
        ],
      };
    });
    final parsed = ParsedImportedBook(
      title: parsedData['title']! as String,
      author: parsedData['author']! as String,
      format: parsedData['format']! as String,
      chapters: [
        for (final chapter in parsedData['chapters']! as List)
          ParsedBookChapter(
            title: (chapter as Map)['title']! as String,
            text: chapter['text']! as String,
          ),
      ],
    );
    final root = await _root();
    final id = _newId();
    final staging = Directory(
      '${root.path}${Platform.pathSeparator}.$id.tmp',
    );
    final target = Directory('${root.path}${Platform.pathSeparator}$id');
    await staging.create();
    try {
      final chapters = <Chapter>[];
      final files = <String>[];
      for (var index = 0; index < parsed.chapters.length; index++) {
        final source = parsed.chapters[index];
        final name = 'chapter_${index.toString().padLeft(5, '0')}.txt';
        final file = File('${staging.path}${Platform.pathSeparator}$name');
        await file.writeAsString(source.text, encoding: utf8, flush: true);
        files.add(name);
        chapters.add(
          Chapter(
            itemId: '$id:chapter:$index',
            title: source.title,
            volumeName: '',
          ),
        );
      }
      final book = ImportedBook._(
        id: id,
        title: parsed.title,
        author: parsed.author,
        format: parsed.format,
        addedAt: DateTime.now(),
        chapters: chapters,
        chapterFiles: files,
      );
      await File(
        '${staging.path}${Platform.pathSeparator}book.json',
      ).writeAsString(jsonEncode(book._toManifest()), encoding: utf8, flush: true);
      await staging.rename(target.path);
      return book;
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  Future<ImportedBook?> book(String id) async {
    if (!RegExp(_bookIdPattern).hasMatch(id)) return null;
    final root = await _root();
    final manifest = File(
      '${root.path}${Platform.pathSeparator}$id${Platform.pathSeparator}book.json',
    );
    if (!await manifest.exists()) return null;
    try {
      final raw = jsonDecode(await manifest.readAsString(encoding: utf8));
      if (raw is! Map) return null;
      return _fromManifest(raw, expectedId: id);
    } catch (_) {
      return null;
    }
  }

  Future<List<ImportedBook>> books() async {
    final root = await _root();
    final books = <ImportedBook>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final id = entity.path.replaceAll('\\', '/').split('/').last;
      if (!RegExp(_bookIdPattern).hasMatch(id)) continue;
      final book = await this.book(id);
      if (book != null) books.add(book);
    }
    books.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return books;
  }

  Future<String> chapterText(String bookId, String chapterId) async {
    final record = await book(bookId);
    if (record == null) throw const FileSystemException('找不到本地书籍');
    final index = record.chapters.indexWhere((chapter) => chapter.itemId == chapterId);
    if (index < 0) throw const FileSystemException('找不到本地章节');
    final root = await _root();
    final file = File(
      [root.path, bookId, record._chapterFiles[index]].join(
        Platform.pathSeparator,
      ),
    );
    return file.readAsString(encoding: utf8);
  }

  String _newId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final salt = _random.nextInt(1 << 32).toRadixString(16);
    return 'local_${timestamp}_$salt';
  }

  ImportedBook? _fromManifest(Map raw, {required String expectedId}) {
    if (raw['id'] != expectedId || raw['chapters'] is! List) return null;
    final title = raw['title']?.toString().trim() ?? '';
    if (title.isEmpty) return null;
    final chapters = <Chapter>[];
    final files = <String>[];
    for (final value in raw['chapters'] as List) {
      if (value is! Map) continue;
      final id = value['id']?.toString() ?? '';
      final file = value['file']?.toString() ?? '';
      if (id.isEmpty ||
          !file.startsWith('chapter_') ||
          !file.endsWith('.txt') ||
          file.contains('/') ||
          file.contains('\\')) {
        continue;
      }
      chapters.add(
        Chapter(
          itemId: id,
          title: value['title']?.toString() ?? '第${chapters.length + 1}章',
          volumeName: '',
        ),
      );
      files.add(file);
    }
    if (chapters.isEmpty || chapters.length != files.length) return null;
    final addedAt = raw['addedAt'];
    return ImportedBook._(
      id: expectedId,
      title: title,
      author: raw['author']?.toString() ?? '',
      format: raw['format']?.toString() ?? '',
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        addedAt is num ? addedAt.toInt() : 0,
      ),
      chapters: chapters,
      chapterFiles: files,
    );
  }
}

/// Parses a local document synchronously. Production calls this through
/// [Isolate.run]; keeping the pure parser public makes its format handling
/// directly testable without a platform picker.
ParsedImportedBook parseImportedBookBytes({
  required String fileName,
  required Uint8List bytes,
  String? decodedText,
}) {
  final extension = fileName.toLowerCase().split('.').last;
  final title = _fileTitle(fileName);
  if (extension == 'txt') {
    final text = decodedText ?? _decodeText(bytes);
    return _parseTxt(title, text);
  }
  if (extension == 'epub') return _parseEpub(title, bytes);
  throw const FormatException('仅支持 TXT 和 EPUB 文件');
}

ParsedImportedBook _parseTxt(String fileTitle, String source) {
  final normalized = source
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\u0000', '')
      .replaceAll('\f', '\n\n')
      .trim();
  if (normalized.isEmpty) throw const FormatException('TXT 正文为空');
  final lines = normalized.split('\n');
  final headingPattern = RegExp(
    r'^\s*(?:第[0-9０-９零〇一二三四五六七八九十百千万两]+[章节回卷部集篇].*|'
    r'[0-9]{1,5}[.、 ]+\S.*|'
    r'卷[0-9０-９零〇一二三四五六七八九十百千万两]+.*|'
    r'序章|序言|楔子|前言|后记|尾声|番外(?:第.*)?|正文)\s*$',
  );
  final headings = <int>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].trim();
    if (line.isNotEmpty && line.length <= 100 && headingPattern.hasMatch(line)) {
    headings.add(index);
  }
  if (headings.length > _maxImportedChapters) {
    throw const FormatException('章节数量超过支持上限');
  }
  }

  final chapters = <ParsedBookChapter>[];
  if (headings.length > 1) {
    for (var index = 0; index < headings.length; index++) {
      final start = headings[index];
      final end = index + 1 < headings.length ? headings[index + 1] : lines.length;
      final content = lines.sublist(start, end).join('\n').trim();
      if (content.isEmpty) continue;
      chapters.add(
        ParsedBookChapter(title: lines[start].trim(), text: content),
      );
    }
  } else {
    final chapterTitle = headings.isEmpty ? '正文' : lines[headings.first].trim();
    chapters.add(ParsedBookChapter(title: chapterTitle, text: normalized));
  }
  if (chapters.isEmpty) throw const FormatException('TXT 中没有可导入的正文');
  return ParsedImportedBook(
    title: fileTitle,
    author: '',
    format: 'txt',
    chapters: chapters,
  );
}

ParsedImportedBook _parseEpub(String fileTitle, Uint8List bytes) {
  _checkEpubZipLimits(bytes);
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final containerFile = archive.findFile('META-INF/container.xml');
  if (containerFile == null) {
    throw const FormatException('EPUB 缺少 META-INF/container.xml');
  }
  final container = XmlDocument.parse(_decodeXmlBytes(containerFile.content));
  final rootfile = _firstElement(container, 'rootfile');
  final opfPath = rootfile?.getAttribute('full-path');
  if (opfPath == null || opfPath.trim().isEmpty) {
    throw const FormatException('EPUB 目录文件无效');
  }
  final normalizedOpfPath = _resolveArchiveHref('', opfPath);
  if (normalizedOpfPath.isEmpty) {
    throw const FormatException('EPUB 目录路径无效');
  }
  final opfFile = archive.findFile(normalizedOpfPath);
  if (opfFile == null) throw const FormatException('EPUB 目录文件不存在');
  final opf = XmlDocument.parse(_decodeXmlBytes(opfFile.content));
  final elements = opf.rootElement.descendants.whereType<XmlElement>().toList();
  final title = elements
          .where((element) => element.localName == 'title')
          .map((element) => element.innerText.trim())
          .firstWhere((value) => value.isNotEmpty, orElse: () => fileTitle);
  final author = elements
      .where((element) => element.localName == 'creator')
      .map((element) => element.innerText.trim())
      .firstWhere((value) => value.isNotEmpty, orElse: () => '');
  final manifest = <String, ({String href, String mediaType})>{};
  for (final element in elements.where((element) => element.localName == 'item')) {
    final id = element.getAttribute('id');
    final href = element.getAttribute('href');
    if (id == null || href == null || id.isEmpty || href.isEmpty) continue;
    manifest[id] = (
      href: href,
      mediaType: element.getAttribute('media-type') ?? '',
    );
  }
  final spine = elements.where((element) => element.localName == 'itemref');
  final baseDirectory = normalizedOpfPath.contains('/')
      ? normalizedOpfPath.substring(0, normalizedOpfPath.lastIndexOf('/'))
      : '';
  final chapters = <ParsedBookChapter>[];
  for (final itemRef in spine) {
    final id = itemRef.getAttribute('idref');
    final item = id == null ? null : manifest[id];
    if (item == null ||
        !(item.mediaType.contains('xhtml') || item.mediaType.contains('html'))) {
      continue;
    }
    final path = _resolveArchiveHref(baseDirectory, item.href);
    if (path.isEmpty) continue;
    final contentFile = archive.findFile(path);
    if (contentFile == null) continue;
    final source = _decodeXmlBytes(contentFile.content);
    final document = html_parser.parse(source);
    final body = document.body;
    if (body == null) continue;
    final chapterTitle = body
            .querySelector('h1, h2, h3, h4, h5, h6')
            ?.text
            .trim() ??
        '';
    final text = _normalizeHtmlText(_htmlNodeText(body));
    if (text.isEmpty) continue;
    chapters.add(
      ParsedBookChapter(
        title: chapterTitle.isEmpty ? '第${chapters.length + 1}章' : chapterTitle,
        text: text,
      ),
    );
  }
  if (chapters.isEmpty) throw const FormatException('EPUB 中没有可阅读的章节');
  return ParsedImportedBook(
    title: title,
    author: author,
    format: 'epub',
    chapters: chapters,
  );
}

XmlElement? _firstElement(XmlDocument document, String localName) {
  for (final element in document.rootElement.descendants.whereType<XmlElement>()) {
    if (element.localName == localName) return element;
  }
  return null;
}

void _checkEpubZipLimits(Uint8List bytes) {
  if (bytes.length < 22) throw const FormatException('EPUB 文件不是有效的 ZIP');
  final view = ByteData.sublistView(bytes);
  final minOffset = max(0, bytes.length - 65557);
  var endOffset = -1;
  for (var offset = bytes.length - 22; offset >= minOffset; offset--) {
    if (view.getUint32(offset, Endian.little) == 0x06054b50) {
      endOffset = offset;
      break;
    }
  }
  if (endOffset < 0) throw const FormatException('EPUB ZIP 目录损坏');
  final entries = view.getUint16(endOffset + 10, Endian.little);
  final directorySize = view.getUint32(endOffset + 12, Endian.little);
  final directoryOffset = view.getUint32(endOffset + 16, Endian.little);
  if (entries == 0xffff || directorySize == 0xffffffff || directoryOffset == 0xffffffff) {
    throw const FormatException('暂不支持 ZIP64 格式 EPUB');
  }
  if (entries > _maxEpubEntries || directoryOffset + directorySize > endOffset) {
    throw const FormatException('EPUB 目录超出支持范围');
  }
  var offset = directoryOffset;
  var expandedBytes = 0;
  for (var index = 0; index < entries; index++) {
    if (offset + 46 > bytes.length || view.getUint32(offset, Endian.little) != 0x02014b50) {
      throw const FormatException('EPUB ZIP 目录条目损坏');
    }
    final compressed = view.getUint32(offset + 20, Endian.little);
    final expanded = view.getUint32(offset + 24, Endian.little);
    final nameLength = view.getUint16(offset + 28, Endian.little);
    final extraLength = view.getUint16(offset + 30, Endian.little);
    final commentLength = view.getUint16(offset + 32, Endian.little);
    if (compressed == 0xffffffff || expanded == 0xffffffff) {
      throw const FormatException('暂不支持 ZIP64 格式 EPUB');
    }
    if (compressed == 0 && expanded > 0 ||
        compressed > 0 && expanded / compressed > 1000) {
      throw const FormatException('EPUB 压缩比例异常');
    }
    expandedBytes += expanded;
    if (expandedBytes > _maxExpandedEpubBytes) {
      throw const FormatException('EPUB 解压后超过 64 MB');
    }
    offset += 46 + nameLength + extraLength + commentLength;
    if (offset > directoryOffset + directorySize) {
      throw const FormatException('EPUB ZIP 目录条目越界');
    }
  }
}

String _resolveArchiveHref(String baseDirectory, String href) {
  final withoutSuffix = href.split('#').first.split('?').first;
  if (withoutSuffix.isEmpty || Uri.tryParse(withoutSuffix)?.hasScheme == true) {
    return '';
  }
  String decoded;
  try {
    decoded = Uri.decodeComponent(withoutSuffix).replaceAll('\\', '/');
  } on FormatException {
    return '';
  }
  final parts = <String>[];
  if (!decoded.startsWith('/')) {
    parts.addAll(baseDirectory.split('/').where((part) => part.isNotEmpty));
  }
  parts.addAll(decoded.split('/'));
  return _normalizeArchivePath(parts.join('/'));
}

String _normalizeArchivePath(String path) {
  final parts = <String>[];
  for (final part in path.replaceAll('\\', '/').split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  return parts.join('/');
}

String _htmlNodeText(dom.Node node) {
  if (node is dom.Text) return node.data;
  if (node is! dom.Element) return '';
  final tag = node.localName;
  if (const {'script', 'style', 'noscript', 'nav'}.contains(tag)) return '';
  if (tag == 'br') return '\n';
  final block = const {
    'address', 'article', 'aside', 'blockquote', 'dd', 'div', 'dl', 'dt',
    'figcaption', 'figure', 'footer', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'header', 'li', 'main', 'ol', 'p', 'section', 'table', 'tr', 'ul',
  }.contains(tag);
  final body = node.nodes.map(_htmlNodeText).join();
  return block ? '\n$body\n' : body;
}

String _normalizeHtmlText(String value) => value
    .replaceAll('\r', '')
    .split('\n')
    .map((line) => line.replaceAll(RegExp(r'[\t\u00a0 ]+'), ' ').trim())
    .where((line) => line.isNotEmpty)
    .join('\n\n')
    .trim();

String _decodeXmlBytes(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }
  var start = bytes.length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf
      ? 3
      : 0;
  return utf8.decode(bytes.sublist(start), allowMalformed: true);
}

String _decodeText(Uint8List bytes) => _decodeXmlBytes(bytes);

String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var offset = 0; offset + 1 < bytes.length; offset += 2) {
    units.add(littleEndian
        ? bytes[offset] | (bytes[offset + 1] << 8)
        : (bytes[offset] << 8) | bytes[offset + 1]);
  }
  if (bytes.length.isOdd) units.add(0xfffd);
  return String.fromCharCodes(units);
}

String _fileTitle(String fileName) {
  final leaf = fileName.replaceAll('\\', '/').split('/').last;
  final dot = leaf.lastIndexOf('.');
  final name = (dot > 0 ? leaf.substring(0, dot) : leaf).trim();
  return name.isEmpty ? '未命名书籍' : name;
}
