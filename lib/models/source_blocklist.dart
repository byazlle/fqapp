/// 远程屏蔽名单：万一某家第三方源（CMS / 西饭 / 河马）的地址失效或不再
/// 可用，只需改仓库里的 `remote/source_blocklist.json` 并推送，所有客户端
/// 在下次启动（或打开设置页）时就会自动停用对应源——不需要重新发版。
///
/// 名单按「源 ID」与「域名」两个维度匹配：
/// - 源 ID：直接命中 `ContentSource.id`（内置源如 `builtin:xifan`）。
/// - 域名：命中自定义 CMS 源的 `baseUrl` 主机名（含子域名），用于把某一
///   整条 CMS 线路停掉。
///
/// 匹配不上或文件拉取失败时一律放行（不影响番茄内置源），失败只是「这次
/// 没有新名单」，上一次成功的名单会缓存本地继续生效。
library;

import 'content_source.dart';

/// 一份屏蔽名单。空名单等于不屏蔽任何源。
class SourceBlocklist {
  const SourceBlocklist({
    this.sourceIds = const <String>{},
    this.hosts = const <String>{},
    this.message = '',
  });

  const SourceBlocklist.empty()
    : sourceIds = const <String>{},
      hosts = const <String>{},
      message = '';

  /// 被停用的源 ID 集合。
  final Set<String> sourceIds;

  /// 被停用的主机名集合（小写，不含端口与路径）。
  final Set<String> hosts;

  /// 停用原因，展示给用户；为空时用默认文案。
  final String message;

  bool get isEmpty => sourceIds.isEmpty && hosts.isEmpty;

  /// 该源是否被名单停用。番茄内置源永不被屏蔽。
  bool blocks(ContentSource source) {
    if (source.protocol == SourceProtocol.fanqie) return false;
    if (sourceIds.contains(source.id)) return true;
    if (hosts.isEmpty) return false;
    final host = _hostOf(source.baseUrl);
    if (host.isEmpty) return false;
    for (final blocked in hosts) {
      if (host == blocked || host.endsWith('.$blocked')) return true;
    }
    return false;
  }

  /// 用户添加自定义源时拦截：主机被停用时不允许新增。
  bool blocksHost(String baseUrl) {
    if (hosts.isEmpty) return false;
    final host = _hostOf(baseUrl);
    if (host.isEmpty) return false;
    for (final blocked in hosts) {
      if (host == blocked || host.endsWith('.$blocked')) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'sourceIds': sourceIds.toList()..sort(),
    'hosts': hosts.toList()..sort(),
    'message': message,
  };

  static SourceBlocklist fromJson(Object? raw) {
    if (raw is! Map) return const SourceBlocklist.empty();
    return SourceBlocklist(
      sourceIds: _stringSet(raw['sourceIds'] ?? raw['blockedSourceIds']),
      hosts: _stringSet(raw['hosts'] ?? raw['blockedHosts']),
      message: raw['message'] is String ? (raw['message'] as String).trim() : '',
    );
  }

  static Set<String> _stringSet(Object? raw) {
    if (raw is! List) return const <String>{};
    return {
      for (final item in raw)
        if (item is String && item.trim().isNotEmpty) item.trim().toLowerCase(),
    };
  }

  static String _hostOf(String baseUrl) {
    if (baseUrl.isEmpty) return '';
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) return '';
    return uri.host.toLowerCase();
  }

  @override
  bool operator ==(Object other) =>
      other is SourceBlocklist &&
      message == other.message &&
      _setEquals(sourceIds, other.sourceIds) &&
      _setEquals(hosts, other.hosts);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(sourceIds),
    Object.hashAllUnordered(hosts),
    message,
  );

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}
