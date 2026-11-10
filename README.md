# 🎵 Myune Music

<div align="center">

### 基于 Flutter 构建的跨平台本地音乐播放器

<!-- 技术与协议胶囊徽章 -->
<p align="center">
  <a href="https://flutter.dev/"><img src="https://img.shields.io/badge/Flutter-3.47%2B-blue?logo=flutter" alt="Flutter" /></a>
  <img src="https://img.shields.io/badge/Platforms-Windows%20%7C%20Linux-brightgreen" alt="Platforms" />
  <img src="https://img.shields.io/badge/lang-Rust-orange?logo=rust" alt="Rust" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-lightgrey" alt="License" /></a>
</p>

<!-- Trendshift 趋势荣誉卡片 -->
<p align="center">
  <a href="https://trendshift.io/repositories/18744?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-18744" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/18744/weekly" alt="xiaobaimc/myune_music | Trendshift Weekly" height="55" /></a>
  &nbsp;&nbsp;
  <a href="https://trendshift.io/repositories/18744?utm_source=repository-badge&amp;utm_medium=badge&amp;utm_campaign=badge-repository-18744" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/repositories/18744" alt="xiaobaimc/myune_music | Trendshift Daily" height="55" /></a>
</p>

</div>

---

## ✨ 特性
* 💻 支持 **Windows / Linux** 双平台
* 🎶 歌曲管理：支持 **文件夹歌单** 与 **手动歌单**
* 🧠 自动按 **歌手** 与 **专辑** 分类
* 🎨 使用 [Material 3](https://m3.material.io/) 组件与配色
* 📝 多种歌词支持：内嵌歌词、本地 `lrc、yrc、qrc、krc 文件`、网络歌词源，支持逐字歌词
* 🔊 提供多种音频滤镜与EQ支持
* ✨ 可自定义主题配色、字体、背景图
* 🧩 支持 **音频独占模式**（仅 Windows）
* ⚙️ **全局快捷键**支持
* 🎵 读取使用和写入 **ReplayGain** 标签
* 🔍 支持模糊搜索拼音搜索与首拼搜索
* 🎤 支持实时音频分析 (该页面默认被隐藏，可在 设置 → 个性化 → 页面可见性设置 手动开启)

## 🔧关于 Linux

对于0.9.1及以下的版本，需要安装 `libmpv`

例如 **Ubuntu/Debian**

``` bash
sudo apt install libmpv-dev mpv 
```

对于0.9.2及以上版本，需要安装 `keybinder-3.0` 以使用全局快捷键

例如 **Ubuntu/Debian**

``` bash
sudo apt install keybinder-3.0
```

如果遇到快捷方式（.desktop）不显示图标的问题 请参考 [issues #114](https://github.com/xiaobaimc/myune_music/issues/114)

## 📸 软件截图



<div align="center">

### 主界面
<img src="screenshot/d5302549c843f8c1d95a80a28a247eda.png" alt="歌单与歌曲列表" width="800" />

</div>

<div align="center">

### 播放页面

<img src="screenshot/ad5e772b9af3a76ad2dbb0f6b4033ee8.png" alt="播放页与逐字歌词" width="800" />

</div>

<div align="center">

### 音频分析

<img src="screenshot/5d7a327730cade5be45417d2f9444acf.png" alt="播放页与逐字歌词" width="800" />


</div>

> 该页面默认被隐藏，可在 设置 → 个性化 → 页面可见性设置 手动开启
---

## 🎶 桌面歌词
由于 [Flutter](https://flutter.dev/) 暂不支持多窗口功能，因此暂未提供桌面歌词
可使用以下第三方工具替代：

* [Lyricify Lite](https://apps.microsoft.com/detail/9nltpsv395k2)
* [BetterLyrics](https://apps.microsoft.com/detail/9p1wcd1p597r)

> 以上软件非本人开发，请支持原作者 🙏

## 🌐 歌词

### 歌词来源与优先级

软件会按照 **歌词来源优先级** 中的顺序依次尝试获取，默认顺序：

```
内嵌歌词 → 外置 LRC → 外置 KRC → 外置 QRC → 外置 YRC → 网络歌词
```

可在「设置 → 个性化 → 歌词来源优先级」中调整顺序

> 外置歌词文件需与歌曲**同名且位于同一目录**，目前仅支持 **UTF-8** 编码

### 网络歌词

在「设置 → 常规」中启用 **从网络获取歌词** 后，若上述来源均未取到歌词，则自动从网络获取

软件默认提供三个源可供选择，三个源全部支持逐字 + 翻译+ 注音的获取

> 软件默认不会显示注音，如有需要请将```同时间戳歌词行数```设为3或以上

当前选中的源未匹配到歌曲时，会自动使用其他源进行匹配

> 特别感谢 [lyricGeter](https://github.com/WisteriaZy/lyricGeter/) 提供的歌词获取以及处理逻辑

### 歌词解析

假设有如下格式的歌词：

>[02:55.031]照らされた世界 咲き誇る大切な人
>
>[02:55.031]在这阳光普照的世界 骄傲绽放的重要之人
>
>[02:55.031]te ra sa re ta se ka i sa ki ho ko ru ta i se tsu na hi to

三句歌词时间戳相同，软件会识别为同一句歌词的不同行，从上到下依次对应 **原文 / 翻译 / 罗马音**

此时可通过「歌词显示设置 → 同时间戳歌词行数」控制显示行数：例如设为 `2`，最后一行（罗马音）将不再显示

### 逐字歌词

支持两种格式，软件会自动识别，无需手动设置：

>[00:15.237]悴[00:15.742]ん[00:15.908]だ[00:16.200]心

或：

>[00:15.237]<00:15.237>悴<00:15.742>ん<00:15.908>だ

---

## 📦 内嵌元数据支持

| 文件格式     | 元数据格式                     |
|-------------|------------------------------|
| AAC (ADTS)  | `ID3v2`, `ID3v1`             |
| Ape         | `APE`, `ID3v2`, `ID3v1`      |
| AIFF        | `ID3v2`, `Text Chunks`       |
| FLAC        | `Vorbis Comments`, `ID3v2`   |
| MP3         | `ID3v2`, `ID3v1`, `APE`      |
| MP4         | `iTunes-style ilst`          |
| MPC         | `APE`, `ID3v2`, `ID3v1`      |                        
| Opus        | `Vorbis Comments`            |
| Ogg Vorbis  | `Vorbis Comments`            |
| Speex       | `Vorbis Comments`            |
| WAV         | `ID3v2`, `RIFF INFO`         |
| WavPack     | `APE`, `ID3v1`               |

## 🎵 支持的音频格式

底层使用 mpv，依赖 FFmpeg 解码，理论上支持绝大多数音频格式

部分格式需在「设置 → 高级」中启用 **允许添加任何格式的文件** 后方可添加到歌单

> 可参阅 [media-kit 支持格式列表](https://github.com/media-kit/media-kit#supported-formats) 作为参考

---

## ☁️ 网络媒体（WebDAV / FTP）

左侧导航「网络媒体」可以直接挂载 NAS / 网盘上的音乐库，不需要先把文件拷到本地。

### 支持的协议

| 协议 | 说明 |
| --- | --- |
| **WebDAV** | 群晖 WebDAV Server、Nextcloud / ownCloud、坚果云、绿联、极空间等；支持 HTTP / HTTPS 与 Basic 认证 |
| **FTP** | 标准被动模式（PASV）+ 二进制传输；支持匿名与账号密码登录 |

> 暂不支持 FTPS / SFTP；FTP 为明文协议，公网使用请改用 WebDAV over HTTPS。

### 使用方式

1. 进入「网络媒体」→「添加网络源」，填写地址、端口、根路径与账号；
2. 点「测试连接」确认可访问后保存；
3. 选中网络源即可浏览目录。列表**只显示文件夹与音频文件**，网盘里的视频、图片、文档不会混进来。

### 播放与队列

* 单击文件立即播放；行尾按钮可「立即播放」或「加入播放队列」；
* 顶部「播放全部」把当前目录的音频一次性加入播放队列，不用逐首点；
* 「更多 → 递归扫描并播放 / 递归扫描并加入队列」会把**所有子目录**里的音频一次性收集起来（默认上限 5000 首、8 层深度），适合「歌手/专辑」多层目录的曲库；
* 「更多 → 点击行为」可切换单击是「立即播放」还是「加入队列」。

### 加入歌单 / 全部歌曲

网络媒体的音频和本地文件一样可以进歌单，重启后不会丢：

* 「更多 → 全部加入歌单…」或单曲行尾「⋮ → 加入歌单…」：弹窗选一个已有歌单；
* 「更多 → 全部加入「全部歌曲」」或单曲行尾「⋮ → 加入「全部歌曲」」：自动落到内置的
  **「网络媒体收藏」**歌单。因为「全部歌曲」是由所有歌单聚合出来的虚拟列表，本身没有可追加的
  存储，所以用这个真实落盘的容器歌单承载，加进去之后左侧歌单和「全部歌曲」里都能看到；
* 「更多 → 递归扫描并加入歌单 / 递归扫描并加入「全部歌曲」」：一次把整棵目录树存进去。

### 标签 / 封面 / 歌词（预加载）

网盘上的音频没有本地路径，Rust 标签解析器读不到，所以会按需下载一份到临时目录再解析：

* **滚动到哪读到哪**：列表行可见时才去读标签，不会一进歌单就把整个曲库全拉一遍；
* **只拉文件头**：先用 HTTP `Range` 只取 2 MB。MP3 的 ID3v2、FLAC 的元数据块、M4A 的 moov、
  OGG 的 comment header 都在文件开头，一次请求就能拿到标题 / 歌手 / 专辑 / 内嵌封面 / 内嵌歌词；
  头部读不出东西时才退回完整下载（单文件上限 48 MB）；
* 读到之后标题、歌手、时长、封面会**就地回填**到列表和「正在播放」，系统媒体会话也会同步刷新；
* **内嵌歌词优先**：播放时先读文件内嵌的 LRC，读不到再走原来的在线歌词（酷狗 / 网易 / QQ），
  在线歌词的行为与原版完全一致；
* 读不到标签时不会反复重试，也不会覆盖成「无标签」，避免一次上游 502 把结果记死；
* 缓存目录 `<系统临时目录>/myune_net_cache` 有 400 MB 上限，超出按最久未修改自动清理；
* 不想要这部分流量可以在「设置 → 高级 → 读取网络媒体内嵌标签」关掉，关掉后只用文件名和网盘
  目录封面。

### 实现说明

* **不落盘**：远端文件不会被缓存到本地，播放时由本机流代理（`127.0.0.1:18765-18774`）按需拉流，边下边播；
* **支持拖动进度**：代理实现了 HTTP Range（`200` / `206` + `Content-Range`），并在上游忽略 Range 时自行跳过起始字节，避免拖动后 `loading failed`；
* **元数据与封面**：优先读文件内嵌标签；读不到时标题/歌手从「歌手 - 标题」命名自动拆分，封面回退到目录内的 `cover.jpg` / `folder.jpg` / `albumart.png` 等文件，并写入播放队列持久化，重启后仍显示；
* **失败可诊断**：上游请求失败会自动重试 3 次，并把每次请求写进
  `文档/myune_music/logs/network.log`；`NetworkMediaService.diagnose()` 能直接区分「上游拒绝 / 太慢 /
  不支持 Range」和「本机代理异常」；
* **队列可恢复**：代理端口若被占用会顺延，播放前会按原 token 改写为当前端口，历史队列不会失效；
* 网络源配置（含密码）只保存在本机 `shared_preferences`，不会写进日志。

---

## 🚀 从源码构建


### 环境要求

* 安装 **Rust** 环境
* 安装 **Flutter SDK**，**Dart** 版本需 ≥ 3.10.0，**Flutter** 版本需 ≥ 3.47.0

### 安装依赖

```bash
flutter pub get
```

### 启动项目

```bash
flutter run
```

### 构建项目
```bash
flutter build windows --release # 或对应平台名
```

## ❤️ 贡献与赞助

### 🧩 贡献
* 创建一个 [Issue](https://github.com/xiaobaimc/myune_music/issues)：bug 反馈、新功能请求或优化建议
* 创建一个 [Pull Request](https://github.com/xiaobaimc/myune_music/pulls)：bug 修复、新功能或优化

> 对于新功能的 PR，请先创建一个 Issue 探讨该功能是否需要

提交前建议执行 `flutter analyze` 检查静态分析结果

### ☕ 赞助

* [爱发电](https://ifdian.net/a/xiaobaimc)

---

## 🧱 使用的依赖

| 插件 | 功能 |
| --- | --- |
| [mpv_audio_kit](https://github.com/ales-drnz/mpv_audio_kit) | 音频播放支持 |
| [lofty-rs](https://github.com/serial-ata/lofty-rs) | 读取与写入音频元信息 |
| [anni_mpris_service](https://pub.dev/packages/anni_mpris_service) | D-Bus MPRIS 控件 |
| [silky_scroll](https://pub.dev/packages/silky_scroll) | 平滑滚动效果 |
| [window_manager](https://pub.dev/packages/window_manager) / [tray_manager](https://pub.dev/packages/tray_manager) | 窗口与系统托盘控制 |

更多依赖请查看 [pubspec.yaml](pubspec.yaml)


## 📄 许可证

本项目使用 **Apache License 2.0** 开源许可协议
详细内容请查看根目录下的 [LICENSE](LICENSE) 文件

### 🔤 字体版权说明（Font License）

本项目使用小米公司提供的 **MiSans 字体**，该字体已明确允许**免费商用**

* 字体版权归小米公司所有
* 相关许可协议请查阅：[MiSans 字体知识产权使用许可协议](https://hyperos.mi.com/font-download/MiSans%E5%AD%97%E4%BD%93%E7%9F%A5%E8%AF%86%E4%BA%A7%E6%9D%83%E8%AE%B8%E5%8F%AF%E5%8D%8F%E8%AE%AE.pdf)
* MiSans 官网：[https://hyperos.mi.com/font/](https://hyperos.mi.com/font/)

---

## Star History Chart

[![Star History Chart](https://api.star-history.com/svg?repos=xiaobaimc/myune_music&type=Date)](https://star-history.com/#xiaobaimc/myune_music&Date)
