/// 通用来源条目 / 详情 / 线路模型。
///
/// 适配器负责把各家接口（CMS、西饭、河马、红果网页版……）映射成这套结构，
/// 页面与播放器只认这里，不再绑定某一家字段。
library;

class SourceItem {
  const SourceItem({
    required this.id,
    required this.title,
    required this.sourceId,
    required this.kind,
    this.cover = '',
    this.remarks = '',
  });

  final String id;
  final String title;
  final String sourceId;
  final String kind;
  final String cover;
  final String remarks;
}

class SourceEpisode {
  const SourceEpisode({required this.name, required this.url});

  final String name;
  final String url;
}

class SourceGroup {
  const SourceGroup({required this.name, required this.episodes});

  final String name;
  final List<SourceEpisode> episodes;
}

class SourceDetail {
  const SourceDetail({
    required this.id,
    required this.title,
    required this.sourceId,
    this.cover = '',
    this.description = '',
    this.typeName = '',
    this.year = '',
    this.area = '',
    this.remarks = '',
    this.groups = const [],
  });

  final String id;
  final String title;
  final String sourceId;
  final String cover;
  final String description;
  final String typeName;
  final String year;
  final String area;
  final String remarks;
  final List<SourceGroup> groups;

  SourceGroup? get preferredGroup {
    for (final group in groups) {
      if (group.episodes.any((episode) => episode.url.contains('.m3u8'))) {
        return group;
      }
    }
    return groups.isEmpty ? null : groups.first;
  }
}

class SourceException implements Exception {
  const SourceException(this.message);

  final String message;

  @override
  String toString() => message;
}
