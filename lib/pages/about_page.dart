import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/brand.dart';
import '../widgets/brand/glass.dart';
import '../widgets/brand/fused_app_bar.dart';
import '../widgets/home/home_design.dart';

/// About page: centered logo/name header followed by grouped card rows
/// (version, positioning, source code, feedback, ...).
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  /// Display version, kept in lockstep with pubspec.yaml's
  /// `version`. Without a package_info dependency the value is
  /// static, so test/about_version_test.dart parses the pubspec and fails the
  /// build check when the two drift apart after a version bump.
  static const versionText = '1.3.2 (137)';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outline;
    final palette = HomePalette.of(context);

    return BrandBackdrop(
      eink: palette.eink,
      // 顶栏与内容融为一体：静止时标题坐在品牌底上，滚动后才浮出同色玻璃。
      child: FusedScrollMeter(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: FusedAppBar(
          title: const Text('关于'),
          centerTitle: true,
          canvas: palette.canvas,
        ),
        body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const SizedBox(height: 16),
          Center(child: BrandMark(size: 88, radius: 24, eink: palette.eink)),
          const SizedBox(height: 16),
          Column(
            children: [
              Text(
                Brand.name,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                Brand.latin.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: outline,
                  fontSize: 10,
                  letterSpacing: 3.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                Brand.discipline,
                textAlign: TextAlign.center,
                style: TextStyle(color: outline, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _AboutCard(
            children: [
              _AboutRow(
                icon: Icons.commit_outlined,
                title: '当前版本',
                trailingText: AboutPage.versionText,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _AboutCard(
            children: [
              _AboutRow(
                icon: Icons.info_outline,
                title: '项目介绍',
                subtitle: '聚合小说、短剧、漫剧、漫画与听书的 Windows 桌面客户端',
              ),
              Divider(height: 1, indent: 68),
              _AboutRow(
                icon: Icons.desktop_windows_outlined,
                title: '桌面体验',
                subtitle: '键盘与鼠标操作、滚轮调音量、宽屏两栏，界面可 90%–125% 缩放',
              ),
              Divider(height: 1, indent: 68),
              _AboutRow(
                icon: Icons.public,
                title: '内容来源',
                subtitle: '在线内容来自第三方公开接口，本程序不内置、不分发任何资源',
              ),
              Divider(height: 1, indent: 68),
              _AboutRow(
                icon: Icons.memory,
                title: '技术实现',
                subtitle: 'Rust 核心在进程内运行，签名、解密与缓存都在本机完成',
              ),
              Divider(height: 1, indent: 68),
              _AboutRow(
                icon: Icons.code,
                title: 'Source Code',
                subtitle: 'github.com/byazlle/winFQAPP',
                url: 'https://github.com/byazlle/winFQAPP',
              ),
              Divider(height: 1, indent: 68),
              _AboutRow(
                icon: Icons.feedback_outlined,
                title: '问题反馈',
                subtitle: '前往 GitHub Issues 提交',
                url: 'https://github.com/byazlle/winFQAPP/issues',
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _SupportCard(),
          const SizedBox(height: 28),
          Center(
            child: Text(
              '仅限个人学习研究使用\n请遵守相关法律法规',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: outline, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          ],
        ),
      ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  final List<Widget> children;
  const _AboutCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final String? url;

  const _AboutRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.url,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outline;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: url == null ? null : () => _launchExternalUrl(context, url!),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: theme.colorScheme.primary),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.labelMedium?.copyWith(color: outline),
            ),
      trailing: trailingText != null
          ? Text(trailingText!, style: TextStyle(fontSize: 13, color: outline))
          : url != null
          ? Icon(Icons.arrow_forward, size: 16, color: outline)
          : null,
    );
  }
}

/// 用外部应用打开 [url]。Android 的包可见性可能让浏览器对 canLaunchUrl
/// 不可见，但仍能处理 ACTION_VIEW，所以这里不做预检查，失败统一走可见提示。
Future<void> _launchExternalUrl(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  var launched = false;
  try {
    launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // Report launch failures through the same visible fallback.
  }
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开链接')));
  }
}

/// 支持作者区块：单独一张卡，用爱发电品牌紫着色并配实心按钮，比普通信息行
/// 更醒目。点击只用系统浏览器打开链接，不引入账号、支付、捐赠校验或统计
/// 上报；墨水屏模式下退化为黑白。
class _SupportCard extends StatelessWidget {
  const _SupportCard();

  static const _sponsorUrl = 'https://afdian.com/a/ch6vip';

  /// 爱发电品牌紫，与 README 里 shields.io 徽章同色。
  static const _brandColor = Color(0xFF946CE6);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = HomePalette.of(context);
    final brand = palette.eink ? palette.ink : _brandColor;
    final onBrand = palette.eink ? palette.canvas : Colors.white;
    final tint = brand.withValues(
      alpha: palette.eink ? 0.06 : (palette.dark ? 0.20 : 0.10),
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: tint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: brand.withValues(alpha: 0.35), width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: brand,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.volunteer_activism,
                    size: 20,
                    color: onBrand,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '支持作者',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '如果这个项目对你有帮助，欢迎在爱发电支持我',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _launchExternalUrl(context, _sponsorUrl),
                icon: const Icon(Icons.favorite, size: 18),
                label: const Text('前往爱发电'),
                style: FilledButton.styleFrom(
                  backgroundColor: brand,
                  foregroundColor: onBrand,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
