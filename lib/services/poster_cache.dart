import 'dart:io' as io;

import 'package:file/file.dart' as pfile;
import 'package:file/local.dart' show LocalFileSystem;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// The app's single image cache.
///
/// Covers, posters, avatars and comic pages all share one budgeted store
/// instead of `DefaultCacheManager`'s defaults (200 objects / 30 days):
/// 2000 entries, 30 days, and a 256 MiB byte budget that a maintenance sweep
/// enforces by deleting the least recently modified files. A swept file leaves
/// its database entry behind; the manager notices the missing file on the next
/// read and re-downloads, so the sweep needs no database surgery.
class PosterCache extends CacheManager with ImageCacheManager {
  /// Where [Config]'s default `IOFileSystem` puts the files. Must mirror the
  /// cache key below: the sweep walks this directory directly.
  static const cacheKey = 'fqapp_images_v1';

  /// How long an unused image stays cached.
  static const stalePeriod = Duration(days: 30);

  /// Entry budget, mirroring the reference implementation's 2000 posters.
  static const maxEntries = 2000;

  /// Byte budget for the whole store.
  static const maxBytes = 256 << 20;

  /// 自定义缓存根目录（设置页迁移缓存时写入 `cacheDirOverride`）。
  ///
  /// 非空时，图片缓存的文件与数据库都落在该目录下，和 Hive 数据同处一地，
  /// 迁移/卸载时不会出现「数据搬走了、图片还留在系统临时目录」的割裂。
  /// 必须在 [instance] 首次被访问前赋值（见 main.dart 的启动流程）。
  static String? overrideBaseDir;

  static final PosterCache instance = PosterCache._();

  PosterCache._() : super(_buildConfig());

  /// 按 [overrideBaseDir] 组装缓存配置：默认走系统临时目录；设置过迁移
  /// 目录则文件与数据库都指向该目录。
  ///
  /// 文件和数据库必须同目录：`JsonCacheInfoRepository` 的 `path` 决定缓存
  /// 元数据文件的位置，`fileSystem` 决定图片文件的位置，二者分离会让「库
  /// 里有记录、文件却找不到」。参见 flutter_cache_manager 的 Config 文档。
  static Config _buildConfig() {
    final base = overrideBaseDir;
    if (base == null || base.isEmpty) {
      return Config(
        cacheKey,
        stalePeriod: stalePeriod,
        maxNrOfCacheObjects: maxEntries,
      );
    }
    return Config(
      cacheKey,
      stalePeriod: stalePeriod,
      maxNrOfCacheObjects: maxEntries,
      fileSystem: _BaseDirFileSystem(base, cacheKey),
      repo: JsonCacheInfoRepository(path: '${_joinPath(base, cacheKey)}.json'),
    );
  }

  /// Deletes the oldest files under the cache directory until it fits
  /// [limit]. Returns the number of files removed. Best-effort: an
  /// unremovable file stops the sweep.
  ///
  /// Call this once per launch; the store grows between launches.
  Future<int> enforceBudget({int limit = maxBytes}) async {
    if (kIsWeb) return 0;
    io.Directory root;
    final base = overrideBaseDir;
    if (base != null && base.isNotEmpty) {
      root = io.Directory(_joinPath(base, cacheKey));
    } else {
      try {
        final temporary = await getTemporaryDirectory();
        root = _join(temporary, cacheKey);
      } catch (_) {
        return 0;
      }
    }
    return enforceImageCacheBudget(root: root, limit: limit);
  }
}

/// The sweep proper, split from [PosterCache.enforceBudget] so tests can run
/// it against a scratch directory without touching `path_provider`.
Future<int> enforceImageCacheBudget({
  required io.Directory root,
  required int limit,
}) async {
  if (!await root.exists()) return 0;
  final entries = <({io.File file, int size, DateTime modified})>[];
  var total = 0;
  await for (final entity in root.list()) {
    if (entity is! io.File) continue;
    try {
      final stat = await entity.stat();
      if (stat.type != io.FileSystemEntityType.file) continue;
      total += stat.size;
      entries.add((file: entity, size: stat.size, modified: stat.modified));
    } catch (_) {
      // A file that vanishes mid-sweep neither counts nor blocks.
    }
  }
  if (total <= limit) return 0;

  entries.sort((a, b) => a.modified.compareTo(b.modified));
  var removed = 0;
  for (final entry in entries) {
    if (total <= limit) break;
    try {
      await entry.file.delete();
      total -= entry.size;
      removed++;
    } catch (_) {
      break;
    }
  }
  return removed;
}

io.Directory _join(io.Directory base, String key) =>
    io.Directory(_joinPath(base.path, key));

/// 拼接 `<base>/<key>`，容忍 [base] 末尾已经带分隔符。
String _joinPath(String base, String key) {
  final separator = io.Platform.pathSeparator;
  final parent = base.endsWith(separator)
      ? base.substring(0, base.length - separator.length)
      : base;
  return '$parent$separator$key';
}

/// 把缓存文件写到指定根目录下的 [FileSystem] 实现。
///
/// `flutter_cache_manager` 自带的 `IOFileSystem` 固定使用
/// `getTemporaryDirectory()`，无法跟随用户在设置里选择的迁移目录；这里沿用
/// 同样的 `package:file` 本地文件系统，只把根目录换成 [baseDir]。
class _BaseDirFileSystem implements FileSystem {
  _BaseDirFileSystem(this.baseDir, this.cacheKey);

  final String baseDir;
  final String cacheKey;

  @override
  Future<pfile.File> createFile(String name) async {
    const fs = LocalFileSystem();
    final directory = fs.directory(_joinPath(baseDir, cacheKey));
    await directory.create(recursive: true);
    return directory.childFile(name);
  }
}
