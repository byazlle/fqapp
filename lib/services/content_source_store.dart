import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/content_source.dart';
import '../models/source_blocklist.dart';
import 'sources/cms_source_client.dart';

/// 内容源仓库：按内容类型保存「当前使用哪个源」，并负责自定义源的增删、
/// 启停与探活。与现有番茄内容体系解耦——这里只决定“用哪个适配器”，
/// 不直接发内容请求。
///
/// 持久化在一个 JSON 键里，便于导出/迁移，也避免多个键之间不同步。
class ContentSourceStore extends ChangeNotifier {
  ContentSourceStore._();

  static final ContentSourceStore instance = ContentSourceStore._();

  static const _storageKey = 'content_sources.v1';

  List<ContentSource> _sources = List<ContentSource>.of(ContentSource.builtins);
  final Map<String, String> _active = {};
  bool _autoFallback = true;

  /// 远程屏蔽名单：命中的源按「已停用」处理——不可选、不进容错链、不能新开。
  /// 名单只收紧不放宽：即使本地把源打开了，名单命中时依然停用。
  SourceBlocklist _blocklist = const SourceBlocklist.empty();
  bool _ready = false;
  Future<void>? _loading;

  bool get ready => _ready;
  bool get autoFallback => _autoFallback;

  List<ContentSource> get sources => List.unmodifiable(_sources);

  SourceBlocklist get blocklist => _blocklist;

  /// 该源当前是否被远程名单停用。
  bool isBlocked(ContentSource source) => _blocklist.blocks(source);

  /// 停用原因文案；名单为空或未填写时给默认说明。
  String get blocklistNotice =>
      _blocklist.message.isNotEmpty
      ? _blocklist.message
      : '该来源已暂时停用，请更换其他来源';

  /// 某一内容类型下可用的源（已启用、未被停用且声明支持该类型）。
  /// 用于自动容错候选。
  List<ContentSource> forKind(String kind) => _sources
      .where((source) => source.enabled && !isBlocked(source) && source.supports(kind))
      .toList(growable: false);

  /// 某一内容类型下声明支持的全部源（含已关闭的），用于设置页展示与启停。
  List<ContentSource> allForKind(String kind) => _sources
      .where((source) => source.supports(kind))
      .toList(growable: false);

  ContentSource? sourceById(String id) {
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  String activeIdFor(String kind) => _active[kind] ?? defaultSourceId;

  ContentSource activeFor(String kind) {
    final selected = sourceById(activeIdFor(kind));
    if (selected != null &&
        selected.enabled &&
        !isBlocked(selected) &&
        selected.supports(kind)) {
      return selected;
    }
    return ContentSource.fanqie;
  }

  /// 自动容错时的候选顺序：当前源优先，其余已启用的同类型源按内置→自定义、
  /// 原顺序排列。
  List<ContentSource> fallbackChain(String kind) {
    final active = activeFor(kind);
    final rest = forKind(kind).where((source) => source.id != active.id);
    return [active, ...rest];
  }

  Future<void> load() {
    if (_ready) return Future<void>.value();
    return _loading ??= _load();
  }

  @visibleForTesting
  void resetForTest() {
    _sources = List<ContentSource>.of(ContentSource.builtins);
    _active.clear();
    _autoFallback = true;
    _blocklist = const SourceBlocklist.empty();
    _ready = false;
    _loading = null;
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _sources = _mergeSources(decoded['sources']);
          final active = decoded['active'];
          if (active is Map) {
            for (final entry in active.entries) {
              if (entry.key is String && entry.value is String) {
                _active[entry.key as String] = entry.value as String;
              }
            }
          }
          _autoFallback = decoded['autoFallback'] != false;
        }
      }
    } catch (_) {
      // 配置损坏时退回内置源，不阻塞设置页。
      _sources = List<ContentSource>.of(ContentSource.builtins);
      _active.clear();
      _autoFallback = true;
    }
    _normalizeActive();
    _ready = true;
    notifyListeners();
  }

  /// 内置源始终以代码定义为准（名称/协议/支持的类型的升级由版本决定），
  /// 只保留用户对 enabled 的选择；自定义源原样保留。
  List<ContentSource> _mergeSources(Object? raw) {
    final saved = <String, ContentSource>{};
    if (raw is List) {
      for (final item in raw) {
        final source = ContentSource.fromJson(item);
        if (source != null) saved[source.id] = source;
      }
    }
    final merged = <ContentSource>[];
    for (final builtin in ContentSource.builtins) {
      final previous = saved.remove(builtin.id);
      merged.add(
        previous == null
            ? builtin
            : builtin.copyWith(enabled: previous.enabled),
      );
    }
    merged.addAll(saved.values.where((source) => !source.builtin));
    return merged;
  }

  void _normalizeActive() {
    for (final kind in contentKindLabels.keys) {
      final selected = sourceById(activeIdFor(kind));
      if (selected == null ||
          !selected.supports(kind) ||
          !selected.enabled ||
          isBlocked(selected)) {
        _active[kind] = defaultSourceId;
      }
    }
  }

  /// 应用远程屏蔽名单。名单变化时把指向被停用源的当前选择重置回番茄。
  void applyBlocklist(SourceBlocklist blocklist) {
    if (_blocklist == blocklist) return;
    _blocklist = blocklist;
    _normalizeActive();
    notifyListeners();
  }

  Future<void> setActive(String kind, String sourceId) async {
    final selected = sourceById(sourceId);
    if (selected == null || !selected.supports(kind) || !selected.enabled) {
      return;
    }
    if (isBlocked(selected)) return; // 被远程名单停用的源不可选
    _active[kind] = sourceId;
    notifyListeners();
    await _persist();
  }

  Future<void> setEnabled(String sourceId, bool enabled) async {
    final index = _sources.indexWhere((source) => source.id == sourceId);
    if (index < 0) return;
    final source = _sources[index];
    if (source.id == defaultSourceId && !enabled) return; // 内置番茄不可关
    if (enabled && isBlocked(source)) return; // 被停用的源打不开
    _sources[index] = source.copyWith(enabled: enabled);
    if (!enabled) {
      for (final entry in _active.entries.toList()) {
        if (entry.value == sourceId) _active[entry.key] = defaultSourceId;
      }
    }
    notifyListeners();
    await _persist();
  }

  Future<void> setAutoFallback(bool value) async {
    if (_autoFallback == value) return;
    _autoFallback = value;
    notifyListeners();
    await _persist();
  }

  Future<ContentSource?> addCustom({
    required String name,
    required String url,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) return null;
    final normalized = _normalizeUrl(url);
    if (normalized == null) return null;
    final existing = _sources.any(
      (source) => source.baseUrl == normalized && source.protocol == SourceProtocol.cms,
    );
    if (existing) return null;
    // 远程名单停用的主机不允许新增自定义源。
    if (_blocklist.blocksHost(normalized)) return null;
    final source = ContentSource(
      id: _newId(),
      name: trimmed,
      protocol: SourceProtocol.cms,
      baseUrl: normalized,
      kinds: const {'video', 'manju'},
    );
    _sources.add(source);
    notifyListeners();
    await _persist();
    return source;
  }

  Future<void> removeCustom(String sourceId) async {
    final source = sourceById(sourceId);
    if (source == null || source.builtin) return;
    _sources.removeWhere((item) => item.id == sourceId);
    for (final entry in _active.entries.toList()) {
      if (entry.value == sourceId) _active[entry.key] = defaultSourceId;
    }
    notifyListeners();
    await _persist();
  }

  /// 探活：CMS 源发一次 `ac=list&pg=1`；内置源不需要探活。
  /// 被远程名单停用的源直接返回不可用，不再发请求。
  Future<CmsProbe> probe(ContentSource source) async {
    if (isBlocked(source)) {
      return CmsProbe(ok: false, message: '该来源已停用', elapsedMs: 0);
    }
    if (source.protocol != SourceProtocol.cms || source.baseUrl.isEmpty) {
      return const CmsProbe(ok: true, message: '内置源无需探活', elapsedMs: 0);
    }
    return CmsSourceClient(source.baseUrl).probe();
  }

  Future<void> _persist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _storageKey,
        jsonEncode({
          'sources': [for (final source in _sources) source.toJson()],
          'active': _active,
          'autoFallback': _autoFallback,
        }),
      );
    } catch (_) {
      // 落盘失败不影响本次会话的选择；下次启动回到上一次成功的配置。
    }
  }

  static String? _normalizeUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.userInfo.isNotEmpty) return null;
    var path = uri.path;
    if (path.isEmpty || path == '/') path = '/api.php/provide/vod/';
    final normalized = uri.replace(path: path);
    return (normalized.hasFragment
            ? normalized.removeFragment()
            : normalized)
        .toString();
  }

  static final _random = Random.secure();

  static String _newId() {
    final bytes = List<int>.generate(8, (_) => _random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'custom:$hex';
  }
}
