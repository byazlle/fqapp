/// 内容源模型：把「去哪里取内容」从具体页面里抽出来，按内容类型分别选择。
///
/// 设计参考（仅借鉴结构与协议，不复制其签名/解密实现）：
/// - `jackotom/hongguo-drama`：内置红果 / 西饭 / 河马三来源 + 自定义 CMS 源，
///   用 `mediaSourcesModel` 做来源列表归一化与启停。
/// - `jycao2/hongguoTV`：独立的第三方 CMS（苹果 CMS / TVBox）源模块，
///   源列表与红果内容体系完全隔离，默认不内置任何第三方地址。
library;

enum SourceProtocol {
  /// 现有番茄接口（本项目内置）。
  fanqie,

  /// 红果官网网页版（服务端渲染，无需请求签名）。
  hongguoWeb,

  /// 西饭短剧（无签名 JSON 接口）。
  xifan,

  /// 河马短剧（无签名 JSON 接口）。
  hema,

  /// 通用 CMS：`?ac=list / ac=detail&ids= / ac=detail&wd=`。
  cms,
}

extension SourceProtocolLabel on SourceProtocol {
  String get label => switch (this) {
    SourceProtocol.fanqie => '内置接口',
    SourceProtocol.hongguoWeb => '红果网页版',
    SourceProtocol.xifan => '西饭接口',
    SourceProtocol.hema => '河马接口',
    SourceProtocol.cms => 'CMS 接口',
  };
}

/// `MediaItem.kind` 的展示名。顺序即设置页里的分类顺序。
const Map<String, String> contentKindLabels = {
  'video': '短剧',
  'manju': '漫剧',
  'manga': '漫画',
  'book': '小说',
  'audio': '听书',
};

const String defaultSourceId = 'builtin:fanqie';

class ContentSource {
  const ContentSource({
    required this.id,
    required this.name,
    required this.protocol,
    this.baseUrl = '',
    this.kinds = const <String>{},
    this.builtin = false,
    this.enabled = true,
  });

  final String id;
  final String name;
  final SourceProtocol protocol;

  /// 自定义源 / 需要地址的协议使用；内置番茄源为空。
  final String baseUrl;

  /// 该源能提供的内容类型（`MediaItem.kind`）。
  final Set<String> kinds;
  final bool builtin;
  final bool enabled;

  bool supports(String kind) => kinds.contains(kind);

  ContentSource copyWith({
    String? name,
    String? baseUrl,
    Set<String>? kinds,
    bool? enabled,
  }) => ContentSource(
    id: id,
    name: name ?? this.name,
    protocol: protocol,
    baseUrl: baseUrl ?? this.baseUrl,
    kinds: kinds ?? this.kinds,
    builtin: builtin,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.name,
    'baseUrl': baseUrl,
    'kinds': kinds.toList()..sort(),
    'builtin': builtin,
    'enabled': enabled,
  };

  static ContentSource? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    final protocol = SourceProtocol.values.firstWhere(
      (value) => value.name == raw['protocol'],
      orElse: () => SourceProtocol.cms,
    );
    final kinds = <String>{
      for (final kind in (raw['kinds'] as List? ?? const []))
        if (kind is String && contentKindLabels.containsKey(kind)) kind,
    };
    return ContentSource(
      id: id,
      name: name,
      protocol: protocol,
      baseUrl: raw['baseUrl'] is String ? raw['baseUrl'] as String : '',
      kinds: kinds,
      builtin: raw['builtin'] == true,
      enabled: raw['enabled'] != false,
    );
  }

  /// 内置源。第三方源默认 **关闭**：用户主动开启后才参与切换，避免应用
  /// 在用户不知情时把内容请求发往非官方站点。
  static const fanqie = ContentSource(
    id: defaultSourceId,
    name: '番茄（内置）',
    protocol: SourceProtocol.fanqie,
    kinds: {'book', 'video', 'manju', 'manga', 'audio'},
    builtin: true,
  );
  static const hongguo = ContentSource(
    id: 'builtin:hongguo',
    name: '红果短剧（网页版）',
    protocol: SourceProtocol.hongguoWeb,
    kinds: {'video', 'manju'},
    builtin: true,
    enabled: false,
  );
  static const xifan = ContentSource(
    id: 'builtin:xifan',
    name: '西饭短剧',
    protocol: SourceProtocol.xifan,
    kinds: {'video'},
    builtin: true,
    enabled: false,
  );
  static const hema = ContentSource(
    id: 'builtin:hema',
    name: '河马短剧',
    protocol: SourceProtocol.hema,
    kinds: {'video'},
    builtin: true,
    enabled: false,
  );

  static const builtins = <ContentSource>[fanqie, hongguo, xifan, hema];
}
