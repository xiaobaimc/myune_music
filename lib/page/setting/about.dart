import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
import 'setting_page.dart';

class About extends StatelessWidget {
  const About({super.key});

  // 创建可点击的链接文字
  TextSpan linkTextSpan(BuildContext context, String text, String url) {
    return TextSpan(
      text: text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
        fontSize: 14,
      ),
      recognizer: TapGestureRecognizer()..onTap = () => _openUrl(url),
    );
  }

  // 打开链接
  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('应用信息与说明', style: Theme.of(context).textTheme.titleMedium),
          ElevatedButton.icon(
            onPressed: () {
              showAboutDialog(
                context: context,
                applicationName: 'Myune Music',
                applicationVersion: 'v$appVersion',
                applicationIcon: Image.asset(
                  'assets/images/icon/logo.png',
                  width: 48,
                  height: 48,
                ),
                applicationLegalese: '© 2025 Myune Music · Apache License 2.0',
                children: [
                  const SizedBox(height: 8),
                  const Text('一个简洁的本地音乐播放器', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 12),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: '本软件基于 ',
                          style: TextStyle(fontSize: 14),
                        ),
                        linkTextSpan(
                          context,
                          'Apache License 2.0',
                          'https://www.apache.org/licenses/LICENSE-2.0',
                        ),
                        const TextSpan(
                          text: ' 开源，可在 ',
                          style: TextStyle(fontSize: 14),
                        ),
                        linkTextSpan(
                          context,
                          'GitHub',
                          'https://github.com/xiaobaimc/myune_music',
                        ),
                        const TextSpan(
                          text: ' 查看代码',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: '遇到问题可在 ',
                          style: TextStyle(fontSize: 14),
                        ),
                        linkTextSpan(
                          context,
                          'GitHub Issue',
                          'https://github.com/xiaobaimc/myune_music/issues',
                        ),
                        const TextSpan(
                          text: ' 反馈',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '软件在出现问题时，可能会将相关歌曲信息记录到本地 /log 目录，但不会将其上传',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '软件中的所有联网操作都可以在设置中控制是否开启',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '软件使用小米公司提供的 MiSans 字体，该字体已明确允许免费商用',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text('字体版权归小米公司所有', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: '相关许可协议请查阅：',
                          style: TextStyle(fontSize: 14),
                        ),
                        linkTextSpan(
                          context,
                          'MiSans 字体知识产权使用许可协议',
                          'https://hyperos.mi.com/font-download/MiSans%E5%AD%97%E4%BD%93%E7%9F%A5%E8%AF%86%E4%BA%A7%E6%9D%83%E8%AE%B8%E5%8F%AF%E5%8D%8F%E8%AE%AE.pdf',
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
            icon: const Icon(Icons.info_outline, size: 20),
            label: const Text('关于信息'),
          ),
        ],
      ),
    );
  }
}
