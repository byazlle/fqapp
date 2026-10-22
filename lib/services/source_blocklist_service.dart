import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/source_blocklist.dart';
import 'content_source_store.dart';

/// 远程屏蔽名单服务。
///
/// 启动时（以及每次打开设置页时）从仓库的
/// `remote/source_blocklist.json` 拉取名单并应用到
/// [ContentSourceStore]：
/// - 拉取成功：应用新名单，并写入本地缓存（断网时用上次的）。
/// - 拉取失败：保留本地缓存；没有缓存时视为空名单（不屏蔽任何源）。
///
/// 拉取失败永远不影响应用启动——它只是「这次没有拿到新名单」。
class SourceBlocklistService {
  SourceBlocklistService({this._client, this._store});
  static final SourceBlocklistService instance = SourceBlocklistService();

  /// 名单文件地址（随仓库分发，改完推送即生效，无需发新版）。
  /// 注意分支名是仓库默认分支 `winFQAPP`（该仓库没有 master）。
  static const url =
      'https://raw.githubusercontent.com/byazlle/winFQAPP/winFQAPP/remote/source_blocklist.json';

  static const _storageKey = 'source_blocklist.v1';
  static const _timeout = Duration(seconds: 8);

  final http.Client? _client;
  final ContentSourceStore? _store;

  SourceBlocklist _current = const SourceBlocklist.empty();
  bool _initialized = false;
  Future<void>? _initializing;

  SourceBlocklist get current => _current;

  ContentSourceStore get _targetStore => _store ?? ContentSourceStore.instance;

  /// 启动时调用一次：先应用本地缓存，再后台刷新远程名单。
  /// 重复调用是安全的（并发调用共用同一个 Future）。
  Future<void> initialize() {
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _targetStore.load();
      final cached = await _readCache();
      if (cached != null) _apply(cached);
      await refresh();
    } catch (_) {
      // 初始化失败不阻塞启动；下次打开设置页还会再试。
      _initialized = false;
      _initializing = null;
    }
  }

  /// 拉取远程名单。返回是否拿到了新名单；失败时保持现状。
  Future<bool> refresh() async {
    final injected = _client;
    final client = injected ?? http.Client();
    try {
      final response = await client.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      final parsed = SourceBlocklist.fromJson(decoded);
      _apply(parsed);
      await _writeCache(parsed);
      return true;
    } catch (_) {
      // 网络异常 / 解析失败 / 404：保持当前名单。
      return false;
    } finally {
      // 注入的 client（测试用）由调用方管理生命周期，不在这里关。
      if (injected == null) client.close();
    }
  }

  void _apply(SourceBlocklist blocklist) {
    if (_current == blocklist) return;
    _current = blocklist;
    _targetStore.applyBlocklist(blocklist);
  }

  Future<SourceBlocklist?> _readCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_storageKey);
      if (raw == null || raw.isEmpty) return null;
      return SourceBlocklist.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(SourceBlocklist blocklist) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_storageKey, jsonEncode(blocklist.toJson()));
    } catch (_) {
      // 缓存写不进去不影响本次生效。
    }
  }

  @visibleForTesting
  void resetForTest() {
    _current = const SourceBlocklist.empty();
    _initialized = false;
    _initializing = null;
  }
}
