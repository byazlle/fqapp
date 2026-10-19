// 版本号统一递增工具（P3-⑫）。
//
// 一次改动同时更新两处版本来源，避免 pubspec.yaml 与「关于」页显示漂移：
//   1. pubspec.yaml            -> version: X.Y.Z+BUILD
//   2. lib/pages/about_page.dart -> versionText = 'X.Y.Z (BUILD)'
//
// 用法（在仓库根目录执行）：
//   dart scripts/bump_version.dart 0.9.123+129   # 直接指定完整版本
//   dart scripts/bump_version.dart --patch       # 0.9.122+128 -> 0.9.123+129
//   dart scripts/bump_version.dart --minor       # 0.9.122+128 -> 0.10.0+129
//   dart scripts/bump_version.dart --major       # 0.9.122+128 -> 1.0.0+129
//   dart scripts/bump_version.dart --build       # 仅递增 build 号
//   dart scripts/bump_version.dart --patch --dry-run  # 只打印，不落盘
//
// 退出码：0 成功；64 参数错误；65 读取/解析失败。

import 'dart:io';

const _exitUsage = 64;
const _exitData = 65;

void main(List<String> args) {
  final root = _repoRoot();
  final pubspecFile = File('${root.path}${Platform.pathSeparator}pubspec.yaml');
  final aboutFile = File(
    '${root.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}pages${Platform.pathSeparator}about_page.dart',
  );

  if (!pubspecFile.existsSync()) {
    stderr.writeln('找不到 pubspec.yaml：${pubspecFile.path}');
    exit(_exitData);
  }

  final pubspec = pubspecFile.readAsStringSync();
  final versionRe = RegExp(
    r'^version:[ \t]*(\d+)\.(\d+)\.(\d+)\+(\d+)[ \t]*\r?$',
    multiLine: true,
  );
  final match = versionRe.firstMatch(pubspec);
  if (match == null) {
    stderr.writeln('pubspec.yaml 中的 version 不是 X.Y.Z+BUILD 形式。');
    exit(_exitData);
  }

  var major = int.parse(match.group(1)!);
  var minor = int.parse(match.group(2)!);
  var patch = int.parse(match.group(3)!);
  var build = int.parse(match.group(4)!);

  final explicit = args.where((a) => !a.startsWith('-')).toList();
  final flags = args.where((a) => a.startsWith('-')).toSet();
  final dryRun = flags.contains('--dry-run');

  if (explicit.length > 1) {
    _usage('一次只能指定一个版本号。');
  }

  if (explicit.isNotEmpty) {
    final m = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$',
    ).firstMatch(explicit.single.trim());
    if (m == null) {
      _usage('版本号格式应为 X.Y.Z 或 X.Y.Z+BUILD。');
    }
    major = int.parse(m.group(1)!);
    minor = int.parse(m.group(2)!);
    patch = int.parse(m.group(3)!);
    // 未给 build 时沿用「build 号只增不减」的惯例。
    build = m.group(4) != null ? int.parse(m.group(4)!) : build + 1;
  } else if (flags.contains('--patch')) {
    patch += 1;
    build += 1;
  } else if (flags.contains('--minor')) {
    minor += 1;
    patch = 0;
    build += 1;
  } else if (flags.contains('--major')) {
    major += 1;
    minor = 0;
    patch = 0;
    build += 1;
  } else if (flags.contains('--build')) {
    build += 1;
  } else {
    _usage('请指定新版本号或 --patch/--minor/--major/--build。');
  }

  final semantic = '$major.$minor.$patch';
  final full = '$semantic+$build';

  final newPubspec = pubspec.replaceFirst(versionRe, 'version: $full');
  if (newPubspec == pubspec) {
    stderr.writeln('未能写入 pubspec.yaml：替换未产生变化。');
    exit(_exitData);
  }

  String? newAbout;
  if (aboutFile.existsSync()) {
    final about = aboutFile.readAsStringSync();
    final aboutRe = RegExp(r"versionText\s*=\s*'[^']*'");
    if (!aboutRe.hasMatch(about)) {
      stderr.writeln('about_page.dart 中找不到 versionText，仅更新 pubspec.yaml。');
    } else {
      newAbout = about.replaceFirst(
        aboutRe,
        "versionText = '$semantic ($build)'",
      );
    }
  } else {
    stderr.writeln('找不到 about_page.dart，仅更新 pubspec.yaml。');
  }

  stdout.writeln(
    '版本：${match.group(0)!.replaceFirst('version: ', '')} -> $full',
  );
  if (dryRun) {
    stdout.writeln('--dry-run：未写入任何文件。');
    return;
  }

  pubspecFile.writeAsStringSync(newPubspec);
  stdout.writeln('已更新 ${_rel(root, pubspecFile)}');
  if (newAbout != null) {
    aboutFile.writeAsStringSync(newAbout);
    stdout.writeln('已更新 ${_rel(root, aboutFile)}');
  }
}

Directory _repoRoot() {
  // 优先从脚本位置推导：scripts/bump_version.dart -> 仓库根。
  final script = File.fromUri(Platform.script);
  final byScript = script.parent.parent;
  if (File(
    '${byScript.path}${Platform.pathSeparator}pubspec.yaml',
  ).existsSync()) {
    return byScript;
  }
  // 回退：当前工作目录（要求在仓库根执行）。
  return Directory.current;
}

String _rel(Directory root, File file) {
  final prefix = root.path.endsWith(Platform.pathSeparator)
      ? root.path
      : '${root.path}${Platform.pathSeparator}';
  return file.path.startsWith(prefix)
      ? file.path.substring(prefix.length)
      : file.path;
}

Never _usage(String message) {
  stderr.writeln(message);
  stderr.writeln(
    '用法：dart scripts/bump_version.dart <X.Y.Z+B> | '
    '--patch | --minor | --major | --build [--dry-run]',
  );
  exit(_exitUsage);
}
