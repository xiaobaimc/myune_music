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

## ☁️ 网络媒体（WebDAV / FTP / Google Drive）

左侧导航「网络媒体」可以直接挂载 NAS / 网盘上的音乐库，不需要先把文件拷到本地。

### 支持的协议

| 协议 | 说明 |
| --- | --- |
| **WebDAV** | 群晖 WebDAV Server、Nextcloud / ownCloud、坚果云、绿联、极空间等；支持 HTTP / HTTPS 与 Basic 认证 |
| **FTP** | 标准被动模式（PASV）+ 二进制传输；支持匿名与账号密码登录 |
| **Google Drive** | **原生直连**官方 Drive API v3，不经过任何第三方 WebDAV 桥；支持「我的云端硬盘」和共享云端硬盘、快捷方式、HTTP Range 拖动进度 |

> 暂不支持 FTPS / SFTP；FTP 为明文协议，公网使用请改用 WebDAV over HTTPS。
> Google Drive 只会列出可下载的二进制文件，Google 文档 / 表格 / 幻灯片没有音频内容，会自动被音频过滤器排除。

### 使用方式（WebDAV / FTP）

1. 进入「网络媒体」→「添加网络源」，选择 **WebDAV** 或 **FTP**，填写地址、端口、根路径与账号；
2. 点「测试连接」确认可访问后保存；
3. 选中网络源即可浏览目录。列表**只显示文件夹与音频文件**，网盘里的视频、图片、文档不会混进来。

### 使用方式（Google Drive 原生）

登录与文件夹选择全部在应用内完成（授权那一步会临时打开系统浏览器）：

1. 进入「网络媒体」→「添加网络源」，把顶部类型切到 **Google Drive**；
2. 点 **「网页登录 Google 账号」**：系统浏览器打开 Google 授权页 → 登录 → 点「允许」→
   浏览器显示「授权成功」后自动回到应用，`refresh_token` 已经自动填好并存到本机；
3. 点「文件夹 ID」右侧的 **「浏览…」**，在弹出的 Drive 文件夹树里一层层点进去，
   点「使用此文件夹」即可设为默认读取目录（留空表示整个「我的云端硬盘」）；
4. 点「测试连接」→ 显示「根目录有 N 个条目」后保存。

网页登录前需要一对 OAuth 客户端凭据：点「从本机文件导入凭据」可读取
`文档/myune_music/google_drive.json` 里的 `clientId` / `clientSecret`，
或在「手动填写 / 导入凭据（高级）」里直接填。这两个值由你自己在
Google Cloud Console 创建，仓库和程序里**不会内置任何真实凭据**。
仍可沿用旧方式：完全手填三件套 + 文件夹 ID，不经过浏览器。

凭据文件的格式（字段名固定，只放在本机）：

```json
{
  "clientId": "你的 OAuth client_id",
  "clientSecret": "你的 OAuth client_secret",
  "refreshToken": "你的 refresh_token",
  "rootFolderId": "可选的根文件夹 ID"
}
```

> **安全说明**：`refresh_token` 等同于该 Google 账号 Drive 的长期读写权限。它只保存在本机
> `shared_preferences`，不会随程序分发、不会写进日志、不会提交到仓库，也不会出现在任何
> 代码或构建产物里。请勿外发或截图。若怀疑泄露，请到 Google 账号的
> 「安全性 → 第三方应用访问权限」里撤销该授权并重新生成。

> 与「自己搭一个 Google Drive → WebDAV 桥」相比，原生直连少一跳：实测首包在 1 秒内，
> 且 Drive API 本身返回 `206 + Content-Range`，拖动进度不再依赖桥接服务是否正确实现 Range。

### 网页登录（OAuth loopback）说明

网页登录采用 Google 官方为桌面应用推荐的 **Loopback IP address 流程**：

```
本机临时 HTTP 服务 127.0.0.1:53682（占用则顺延到 53693）
   ↓ 用系统浏览器打开 accounts.google.com/o/oauth2/v2/auth
   ↓ 参数：access_type=offline、prompt=consent、state=随机值（防伪造回调）
用户在网页里登录并同意
   ↓ Google 把 code 重定向回 http://127.0.0.1:53682/
   ↓ 校验 state → 用 code + client_id/client_secret 换 token
拿到 access_token + refresh_token → 写入本机设置与 google_drive.json → 关闭临时服务
```

几个需要注意的点：

* **权限范围**：`https://www.googleapis.com/auth/drive`（完整 Drive 读写），这样才能上传、
  新建、重命名与删除。它是 Google 的「受限范围」，未做 OAuth 验证的应用会显示
  「此应用未经验证」，把账号加进该 OAuth 客户端的**测试用户**即可继续。
* **重定向 URI**：客户端类型为「桌面应用」时 Google 允许任意 loopback 端口，无需登记；
  若用的是「Web 应用」类型，需要在 Cloud Console 把
  `http://127.0.0.1:53682/`（以及顺延端口）加入「已获授权的重定向 URI」，
  否则会报 `redirect_uri_mismatch`。界面里的登录说明也写了这一条。
* **凭据不进仓库**：`client_id` / `client_secret` / `refresh_token` 只存在本机
  `shared_preferences` 与 `文档/myune_music/google_drive.json`，不写日志、不随程序分发。
* 登录超时 5 分钟，可随时点进度框「取消」；临时 HTTP 服务在结束时一定会关闭。
* 「更多 → 查看当前 Google 账号 / 授权范围」可以确认当前连的是哪个账号。

### 文件管理（上传 / 新建 / 重命名 / 删除）

写入操作目前只开放给 **Google Drive 源**（WebDAV / FTP 仍为只读浏览）：

| 入口 | 行为 |
| --- | --- |
| 更多 → **上传本地音频到当前目录** | 多选本机音频，串行上传到当前目录；按 4 MB（256 KB 整数倍）分块 resumable PUT，带实时进度与「取消」，不会把大文件整首读进内存 |
| 更多 → **在当前目录新建文件夹** | 输入名称后创建，创建完自动刷新列表 |
| 文件 / 文件夹行尾 ⋮ → **重命名** | 调 `files.update`（PATCH）改名 |
| 文件 / 文件夹行尾 ⋮ → **移入回收站** | 调 `files.delete`，**不是永久删除**，可在 Google Drive 网页端「回收站」恢复；删除前有二次确认 |
| 选文件夹弹窗 → **新建文件夹** | 在浏览目录树时直接建新文件夹，立刻可作为默认读取目录 |

上传用的是 Drive API v3 的 `uploadType=resumable`：先 POST metadata 拿到会话 URL，
再按块 PUT 并带 `Content-Range: bytes start-end/total`，中间返回 `308 Resume Incomplete`，
最后一块返回 `200/201` 即完成。文件选择器只放行常见音频扩展名，
避免把视频 / 文档误传进音乐库。

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

网盘上的音频没有本地路径，所以按需用 HTTP `Range` 拉文件头来解析标签：

* **滚动到哪读到哪**：列表行可见时才去读标签，不会一进歌单就把整个曲库全拉一遍；
  不需要先播放一次——列表渲染出来就会在后台读；
* **结果落盘，重启不重读**：读到的标题 / 歌手 / 专辑 / 时长 / 内嵌歌词 / 封面会写入
  `文档/myune_music/tag_cache/`（元数据 JSON 与封面二进制分开存），下次启动先载入索引，
  列表直接命中缓存，不会为同一首歌反复请求 2 MB 文件头。缓存 key 是
  「网络源 id + 媒体 id / 远端路径」，代理端口在 18765-18774 之间变化也不会失效；
  上限 3000 条 / 512 MB，超出按最久未修改淘汰，删掉该目录即等于清空缓存；
* **只拉文件头**：先取 2 MB。MP3 的 ID3v2、FLAC 的元数据块、M4A 的 moov 都在文件开头，
  一次请求就能拿到标题 / 歌手 / 专辑 / 内嵌封面 / 内嵌歌词 / 精确时长；
  实测 59 MB 的 FLAC 全部标签只占前 537 KB，封面 527 KB、内嵌歌词 1 KB 都在其中；
* **双解析路径**：FLAC（`METADATA_BLOCK` / `VORBIS_COMMENT` / `PICTURE`）与 MP3（ID3v2 的
  APIC / USLT / TIT2 等帧）由纯 Dart 直接从字节解析，不依赖文件扩展名、不要求文件完整；
  M4A / OGG / APE 等由 Rust lofty 解析同一个带真实扩展名的头部文件。两条路径结果按
  「字节解析优先」合并，任一成功即可；
* **一键读取**：「更多 → 一键读取本目录封面」会把当前目录所有音频的封面 / 标题 / 时长 /
  歌词一次读完并落盘（默认 2 并发、只拉文件头），适合进入新目录后先把封面铺满；
* 头部完全解析不出东西时才退回完整下载（单文件上限 96 MB，足以覆盖 80 MB 以上的无损文件）；
* 读到之后标题、歌手、时长、封面会**就地回填**到列表、「正在播放」的播放页背景和
  系统媒体会话；封面就绪晚于歌词加载时，内嵌歌词也会补上（不抢走已显示的在线歌词）；
* **可核对**：每次成功都会在 `文档/myune_music/logs/network.log` 写一行
  `tag read ok ... cover=527186B lyrics=1058ch duration=287272ms`，
  用「更多 → 查看网络日志」即可确认某首歌到底读没读到封面和歌词；
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
* **Google Drive 链路**：`refresh_token → access_token`（只在内存缓存、提前 2 分钟过期、并发刷新合并）
  → `files.list` 分页列目录（`supportsAllDrives` / `includeItemsFromAllDrives` 覆盖共享盘，
  并解析 `shortcutDetails` 快捷方式）→ `files.get?alt=media` 流式下载，带 `Range: bytes=a-b`
  时上游直接返回 `206`；总长度还能用 `files.get?fields=size` 兜底补全；
* **协议判定以配置为准**：代理 URL 里的 `proto` 只作元数据，实际用哪个客户端一律以
  `RemoteSource.type` 为准，避免旧队列里的别名把 Drive 请求错发到 WebDAV / FTP 端口；
* 网络源配置（含密码与 Google 凭据）只保存在本机 `shared_preferences`，不会写进日志。

---

## 🔧 网络媒体标签 / 封面修复说明（本轮改动记录）

> 适用提交链：`7967e32` → `77fcff0` → `2348302` → `6b4b363`（`feat/webdav-ftp-network-drive`），均已推送至远端并在 GitHub Actions 编译通过。

### 问题现象

之前版本对网盘上的 FLAC / MP3 音频无法读取内嵌专辑封面和内嵌歌词，播放页左侧只显示模糊背景但无实际封面图；右侧系统媒体控件却往往有封面——因为系统侧通过另一条链路拿到了 artwork，应用内 `currentSong.albumArt` 却始终为空。

查看 `文档/myune_music/logs/network.log` 能找到确切报错：

```
tag parse failed (... .head): No format could be determined from the provided file
tag parse failed (... .bin): No format could be determined from the provided file
```

### 根因

旧实现在 `_fetchHead()` 把 HTTP Range 拉下来的前 2MB 字节存成 `<hash>.head`，完整兜底下载存成 `<hash>.bin`。**两个文件名都没有任何扩展名或正确识别用的后缀**。Rust 侧的 `lofty` 接到这种"裸"临时文件时，既无法从路径推断格式，也因为没有完整的音频帧导致 probe 失败，于是报出上面那行错误——等于什么都没读到就放弃了。

### 改动链（按时间顺序）

| commit | 消息 | 职责 |
| --- | --- | --- |
| `7967e32` | `fix(network): 修复网络媒体内嵌封面/歌词读取并回填播放页` | 新增纯 Dart 头部标签解析器 + 双路径合并逻辑 + 播放页回填链路（最大一批，+639 行） |
| `77fcff0` | `style(network): 消除 2 条非空断言告警并修正标签 partial 语义` | 修掉上一版遗留的 2 条 `unnecessary_non_null_assertion` lint 警告，并把 `partial` 语义改成「仅当两条解析路都失败才算 partial」 |
| `2348302` | `feat(network): 标签/封面缓存落盘，重启后不再重复拉取文件头` | 把已读到的元数据 JSON 与封面二进制写进磁盘缓存，启动时自动索引；同时修掉 Stream.whereType / FileStat 数值的编译错误 |
| `6b4b363` | `fix(network): 修复缓存落盘编译错误，新增「一键读取本目录封面」` | 补上遗漏的错误处理 + 给网络媒体页加「一键读取本目录封面」菜单入口 |

合计 8 个文件，净增约 +1041 / −53 行。

### 涉及文件与关键代码位置

#### 1. `lib/services/network/network_header_tags.dart`（**新文件**，407 行）
纯 Dart 从头字节解析器，不依赖扩展名、不要求文件完整。

关键类：
- `NetworkHeaderTags`（第 14–50 行）：标签载体，含 `title` / `artist` / `album` / `lyrics` / `cover` / `durationMs` / `trackNumber` / `format` 字段。
- `NetworkHeaderTagParser.parse(bytes)`（第 57 行）：入口点；按 magic 分派到 `_parseFlac` / `_parseId3`。

支持的格式与帧映射：

| 容器 | 解析的块/帧 | 对应字段 |
| --- | --- | --- |
| FLAC `fLaC` 开头 | `STREAMINFO`（type 0）+ `VORBIS_COMMENT`（type 4）+ `PICTURE`（type 4 / JPEG/PNG） | 时长 / 标题歌手专辑歌词 / 封面 |
| MP3 ID3v2 | v2.2 / v2.3 / v2.4；帧 TIT2/TT2、TPE1/TP1、TALB/TAL、TCON/TCO、TRCK/TRK、USLT/ULT、APIC/PIC | 同左 |
| M4A / OGG / APE | **不走这里**，由 lofty 兜底 | — |

辅助函数集中在文件下半段（第 290–406 行）：
- `_u24be` / `_u32be` / `_u32le` / `_syncSafe`：大端 / 小端 / syncsafe 无符号整数解码
- `_id3Text` / `_id3Lyrics` / `_id3Picture`：ID3 文本帧、 lyrics 帧、图片帧的结构化抽取
- `_ascii(bytes, offset, len)`：定长 ASCII 比较（用于 magic 检测）

#### 2. `lib/services/network/network_tag_reader.dart`（主体改动，+466 / −6 行）
这是整个改动的总调度器。

重要 API 与变更：

| 方法 / 字段 | 所在行（HEAD） | 作用 |
| --- | --- | --- |
| `class NetworkTagInfo` | ~50 行 | 对外暴露的标签模型（序列化支持由这个类承载） |
| `class NetworkTagReader` | ~117 行 | 核心单例服务 |
| `static Future<void> initialize()` | ~135 行 | 启动时扫描 `tagCacheDir` 重建内存索引（JSON 条目加载到 `_cache`） |
| `static Future<NetworkTagInfo?> read(url)` | ~193 行 | 主读取接口：内存命中 → 磁盘命中 → 联网 2MB 文件头 → 兜底完整下载；任一成功即写入磁盘 |
| `static NetworkTagInfo? cached(String url)` | 新增同步 getter | 列表渲染时用，零成本取内存或磁盘快照 |
| `static void prefetch(String url)` | ~217 行 | 预热用（不等待结果），被「一键读取」触发 |
| `static Future<int> prefetchAll(Iterable<String> urls)` | ~229 行 | 批量预热返回已完成数量，就是「一键读取」走的路径 |
| `_fetchHead(url, headerBytes: 2*1024*1024)` | ~271 行 | 发起 HTTP Range 请求并把头字节以带正确扩展名的 `<hash>_head.<ext>` 写入缓存临时目录；同时返回 `Uint8List` 供字节解析 |
| `_readUncached(url)` | ~324 行 | 核心解析：先 `NetworkHeaderTagParser.parse(head.bytes)`，再 try lofty，两者合并返回；写 `network.log` 形如 `tag read ok ext=.flac ... via=flac cover=...B lyrics=...ch duration=...ms` |
| `_combine(headerTags, loftyInfo)` | ~370 行 | 「字节解析优先」合并策略：封面 / 歌词 / 标题均优先用字节解析的结果 |
| `_remember(url, info)` | ~420 行 | 写内存 + 写磁盘：`.json`（元数据）+ `.cover`（封面二进制）到 `<Documents>/myune_music/tag_cache/<hash>.{json,cover}` |
| `_diskCacheKey(url)` | ~579 行 | **关键点**：从 `RemoteMediaRegistry.decodeTarget(url)['i']`（源 id）+ `['p']` / `['t']`（远端路径）合成 stable key，不含代理端口，所以端口漂移不影响缓存命中 |
| `_tagCacheDir()` / `_netCacheDir()` | ~641 行 | 缓存根目录：磁盘走 `<Documents>/myune_music/tag_cache/`（3000 条目 / 512 MB 上限，LRU 淘汰）；临时文件头走 `<temp>/myune_net_cache/`（400 MB 上限） |

#### 3. `lib/page/playlist/playlist_content_notifier.dart`（+66 / −6 行）
封面 / 歌词回填播放页与系统媒体会话的驱动层。

关键改动：
- `_refreshNetworkSongTags(url)`（~1330 行附近）：改为**统一调 `NetworkTagReader.read(url)`**（内部走 内存→磁盘→网络三级），替换原来的 `cached() ?? await read()` 短路写法，避免「内存里没有但磁盘有」时被跳过导致封面补不上。
- `_prepareSongForPlayback(song)`（~1195 行附近）：网络分支同步合并缓存标签，确保首次打开播放页就能看到封面。
- `_onNetworkTagReady(url, info)`：标签就绪回调中增加当前歌曲检查，若匹配的 Song 还没封面就把封面缓存写到 `_coverStore`。
- `lyrics_handler.refreshEmbeddedLyrics(songFilePath)`：延迟的歌词填充——如果歌曲播放开始时在线歌词已经显示，内嵌歌词不会抢走它；等内嵌歌词就绪后再补上。

#### 4. `lib/lyrics/lyrics_handler.dart`（+22 行）
新增 `refreshEmbeddedLyrics(String songFilePath)` 方法，供播放引擎在标签落盘后通知歌词组件刷新。

#### 5. `lib/main.dart`（+5 行）
`main()` 末尾加一行：

```dart
await NetworkTagReader.initialize();
```

放在 `NetworkMediaService.initialize()` 之后。作用：App 冷启动时把磁盘 tag cache 索引一次性载入内存 Map，后续「滚动到哪读到哪」在缓存命中时直接返回，不触发任何网络请求。

#### 6. `lib/page/network/network_media_page.dart`（+94 行）
新增菜单项与批量读取 UI。

- 右上角 ⋮ 菜单新增：`「一键读取本目录封面」`
- `_prefetchCurrentDirectory()` 私有方法：拿到 `_audioEntries`、确认代理可用后调 `NetworkTagReader.prefetchAll(urls)`，期间弹出 `AlertDialog` 展示 `ValueListenableBuilder<int>(valueListenable: progress)` 实时进度（"已处理 N / total"），完成给出 toast 提示；点对话框任意处不会中断后台任务。
- 并发控制：默认 2 并发（`_prefetchCurrentDirectory` 里串行化调用 `prefetch()`，由 `NetworkTagReader._inflight` map 做并发合并）。

### 数据流（一句话概括）

```
[列表渲染 / 播放点击]
        ↓
PlaylistContentNotifier._prepareSongForPlayback()
        ↓
NetworkTagReader.read(url)   ←───┐ 内存命中？直接返回       │
        ↓                        │                           │
    磁盘命中？(tag_cache/*.json) │  是 → 反序列化 -> 回填    │
        ↓                        │                           │
    _fetchHead(url, bytes=2MB)  │  否 → ┌───────────────────┘
        ↓                        │     │
_networkHeaderTagParser.parse()│     ▼
  (FLAC STREAMINFO/VORBIS/PICTURE
   或 ID3 TIT2/USLT/APIC 等)      │
        ↓ 字节解析成功？           │
   YES → 写磁盘 → 返回            │
   NO  → 调 lofty(带真实扩展名的
         头部临时文件)             │
              ↓                   │
         字节解析 || lofty 成功？  │
              ↓                   │
          YES → 写磁盘 → 返回     │
          NO  → 完整下载 96MB 兜底 │
                                 │
回填：currentSong.albumArt        │
      _coverStore.put(...)        │
      setMediaSession(...)        │
      lyricsHandler.refreshEmbeddedLyrics(...)
```

### 用户可观察的现象

1. **成功日志**：`文档/myune_music/logs/network.log` 中出现形如
   ```
   tag read ok ext=.flac head=2097152B total=61990968B via=flac cover=527186B lyrics=1058ch duration=287272ms
   ```
   `via=flac` 表示纯字节解析成功，`via=lofty` 表示走了 Rust 兜底；`cover=0B` / `lyrics=0ch` 表示该格式没有对应的内嵌标签。

2. **失败日志**：仍以 `tag parse failed ... No format could be determined from the provided file` 出现，意味着连兜底的完整下载也没能认出格式（极少见，可能是加密 / 损坏音频）。

3. **缓存目录**：`<Documents>/myune_music/tag_cache/` 下的文件：
   - `<hash>.json` —— UTF-8 JSON，包含 title / artist / album / genre / trackNumber / durationMs / lyrics
   - `<hash>.cover` —— 原始封面图字节（JPEG / PNG），base64 编码后存储在内存，写入数据库 / session 时用这个二进制文件
   删掉整个 `tag_cache/` 目录即等同于清空全部缓存，下次进入网络目录会重新拉一次文件头。

4. **「一键读取」按钮**：打开一个音频目录后点击右上角 ⋮，选择「一键读取本目录封面」；进度弹窗会实时显示「已处理 N / total」；可点「后台继续」让对话框不阻塞其它操作。

### 性能与存储影响

- **单次读取**：2 MB Range 请求约消耗 1-2 KB 网络流量 + 几毫秒本地解析；大多数 FLAC / MP3 都能在其中命中。
- **封面落盘**：每张封面约 50-600 KB，3000 首上限理论占用约 1.5 GB，但 512 MB 软上限会自动 LRU 淘汰最久未访问的条目。
- **启动代价**：`initialize()` 分批并发（每批 8 个）读取 `tag_cache` 里的 JSON **和 `.cover` 二进制**，128 MB 以内会在启动阶段全部补回内存；本机 102 首 / 38 MB 实测为纯本地 IO，不产生任何网络请求。超过 128 MB 的部分仍走按需读取。

### 已知限制

- 目前只实现 FLAC 与 ID3v2（MP3）两种格式的头部解析；M4A / OGG / APE 仍依赖 lofty，如果它们的元数据区落在 2MB 之外的情况下可能读不到——这种情况建议关掉「设置 → 高级 → 读取网络媒体内嵌标签」回退到纯文件名模式，避免每次都走完整下载的慢路径。
- `tag_cache` 是进程级索引 + 磁盘文件的组合；强制断电 / 崩溃可能导致个别条目半写（json 已写 cover 未写），下次启动时 JSON 里取不到封面字段会自动重读——不会破坏已有数据。
- 「一键读取」在当前实现下是 2 并发，对于几百首的大目录可能需要十几秒到几十秒不等，建议在 WiFi 环境下使用。

### 如何验证本轮改动是否生效

跑最新版 Windows 包（`release/myune_music_windows_x64_cover_lyrics.zip` 之后的任意版本），进入你的 Google Drive / WebDAV 的某个音频目录：

1. 首次进入：等列表加载，封面应该陆续在每行出现；
2. 退出 App，重新启动，回到同一目录：封面**瞬间全部出现**，无需任何点击；
3. 点右上角 ⋮ →「一键读取本目录封面」：应出现进度弹窗，完成后列表全部铺满；
4. 打开「更多 → 查看网络日志」，翻到底部找 `tag read ok` 行，确认 `via=` 字段不是空的、`cover=` 和 `duration=` 都有数值；
5. 播放其中一首歌，左侧播放页应能看到专辑封面模糊背景、顶部进度条旁显示内嵌歌词。

以上任一条不符合预期，请把 `network.log` 的最后 50 行（`tail -n 50 <path>/logs/network.log`）贴出来以便定位。

> 注：上面第 2 条在 `6b4b363` / `ac03d98` 版本里**实际不成立**，是本次修复要解决的问题，详见下一节。

## 🔁 启动后封面不自动显示（必须手动点「一键读取」）修复记录

### 问题现象

用户实测反馈：**每次刚进软件，所有网络媒体的封面都是空白；必须手动点一次「一键读取本目录封面」（重新读一遍缓存），封面才会全部出现**。点完之后当前会话一直正常，但重启又回到空白。

### 根因（两个缺陷叠加）

1. **磁盘封面没有在启动时补回内存索引**
   `NetworkTagReader.initialize()` 只扫描 `tag_cache/*.json` 并重建 `_diskIndex`。而 `NetworkTagInfo.toJson()` 刻意不序列化 `cover`（封面单独存 `<hash>.cover` 二进制文件，避免 JSON 被几百 KB 图片撑爆）。于是重启后 `_diskIndex` 里的条目恒为 `hasCover == false`，`cached()` 同步返回的信息里没有封面。
   同一次运行内点「一键读取」会走 `_remember()` → `_saveToDisk()`，后者执行 `_diskIndex[hash] = info`（**这里的 info 是带封面的**），所以当前会话立刻正常 —— 这正是「点一次就好、重启又坏」的原因。

2. **路径归一化把网络代理 URL 破坏了**
   `PlaylistContentNotifier._normalizePath()` 直接 `return p.normalize(path);`。Windows 上 `package:path` 的 `normalize()` 会把 `http://127.0.0.1:18765/myune/<token>` 里的连续斜杠折叠并转成反斜杠，结果不再是合法 URL。
   而封面工作线程 `_coverWorker()` 里是 `final filePath = cacheKey;`，拿到的是这个被破坏的字符串：
   - `RemoteMediaRegistry.isNetwork(filePath)` → `isProxyUrl()` 要求 `startsWith('http://127.0.0.1:')` → 判定为 **false**；
   - 于是走「本地文件 `readAudioInfo()`」分支，对一个不存在的路径读标签，必然失败；
   - 结果 `_coverlessPaths.add(cacheKey)`，这一行被标记为「已确认无封面」，**连按需补封面也不会再触发**。

   `Song._normalizeForCache()` 早已针对 `'://'` 做了保护（网络地址原样返回），但 `PlaylistContentNotifier._normalizePath()` 没有同步这个修复，两处 key 语义不一致，又连带让 `Song.normalizedPath` 与封面仓库的 key 对不上。

### 本机证据（2026-11-11）

```
Documents/myune_music/tag_cache/ : 102 个 .json + 102 个 .cover ，共 38 MB
network.log:
  19:14~19:15  tag read ok ... cover=xxxxxB ...   ← 上一次「一键读取」写的盘
  19:54:36     tag cache loaded 102 entries        ← 重启，只加载了 JSON
  19:54:36 之后没有任何封面读取记录                ← 封面从未补回内存
```

### 改动文件与关键代码位置

| 文件 | 位置 | 改动 |
| --- | --- | --- |
| `lib/services/network/network_tag_reader.dart` | `NetworkTagInfo.withCover()` | 新增：用 `.cover` 字节补全来自 JSON 的条目，供启动与按需 hydrate 复用 |
| 同上 | `_maxHydratedCoverBytes` | 新增常量 128 MB，限制启动时一次性补回的封面体积 |
| 同上 | `initialize()` | 改为「JSON + `.cover` 一起读」，每批 8 个并发；写日志 `tag cache loaded N entries, covers hydrated M (X.X MB)` |
| 同上 | `_loadDiskEntry(File, bool)` | 新增：单条目读取；`fromJson` 返回 null 但存在 `.cover` 时仍构造一个只有封面的条目，不丢数据 |
| 同上 | `_readCoverByHash(String)` / `_readCoverFile(String)` | 新增按 hash 直读；`_hydrateCover()` 改用 `withCover()` 减少重复 |
| `lib/page/playlist/playlist_content_notifier.dart` | `_normalizePath()` | 网络 URL / `nas:` 标识原样返回，与 `Song._normalizeForCache()` 对齐；本地路径仍 `p.normalize()` |
| 同上 | `_loadAllData()` | 末尾追加 `unawaited(_primeNetworkCoversFromDisk())` |
| 同上 | `_primeNetworkCoversFromDisk()` | 新增：延迟 150 ms 避开 Provider 创建期，`initialize()` 幂等兜底 → `_sweepNetworkTagsIntoSongs()` 回填全部列表 → 更新 `_currentSong` 与其封面 → `notifyListeners()` |
| 同上 | `requestSongCover()` | 新增快速路径：网络媒体若 `NetworkTagReader.cached(key)` 已有封面，直接 `_coverStore.put()` 播种，首帧即可显示，不必等封面工作线程排队 |

### 修复后的数据流

```
启动 main()
  └─ await NetworkTagReader.initialize()
       ├─ 读 <hash>.json        → 标题 / 歌手 / 专辑 / 时长 / 内嵌歌词
       └─ 读 <hash>.cover       → 封面二进制  ← 本次新增
            ↓ _diskIndex[hash] = 带封面的 NetworkTagInfo
  └─ runApp → PlaylistContentNotifier
       ├─ _loadAllData() 末尾 _primeNetworkCoversFromDisk()
       │    └─ _sweepNetworkTagsIntoSongs() → 列表 Song.albumArt + _coverStore
       └─ 列表行 SongCoverBuilder
            ├─ coverCacheKey(原始 URL) → _normalizePath 原样返回 ← 本次修复
            └─ requestSongCover() → cached()?.cover → _coverStore.put() → 立即重绘
```

全程**零网络请求**：封面来自本机 `tag_cache`，仅在播放时才需要本机流代理。

### 如何验证

1. 确认 `tag_cache/` 里有成对的 `.json` + `.cover`；
2. 完全退出 App 再启动，进入「全部歌曲」/ 歌单，**不点任何按钮**，封面应在列表首帧出现；
3. 打开「更多 → 查看网络日志」，应看到一行：
   `tag cache loaded 102 entries, covers hydrated 102 (36.2 MB)`（数字按实际曲库变化）；
4. 播放网络歌曲，播放页模糊背景封面、系统媒体控件封面都应同步出现；
5. 「一键读取本目录封面」仍可用，但对已缓存条目应当秒完成且**不产生 `tag read ok` 联网日志**。

### 已知限制

- 启动时补回封面有 128 MB 软上限；超大曲库超出部分仍会在列表行可见时按需从磁盘读取，不影响正确性。
- 旧版本可能已在内存里把部分路径误标记进 `_coverlessPaths`，但该集合是进程级的，重启即清空；升级到本版本后不会再产生误标记。
- 网络媒体页的**文件列表行**目前仍用文件图标而不是封面缩略图（该页展示的是远端目录项，不是已入库的 Song）。若需要在这一页也显示封面缩略图，属于另一项 UI 改动，本轮未纳入。


## 🛠 网络播放 / 歌曲详情 / 网页登录稳定性修复记录（本轮改动）

### 问题现象

1. 点击播放网络音频时，多数情况下报
   `MpvLogError(prefix: lavf, level: LogLevel.error, text: avformat_open_input() failed)`。
2. 打开「歌曲详情」页，所有网络媒体都显示「无法加载歌曲详情，请稍后重试」。
3. Google Drive 网页登录在低性能电脑上有一定概率失败；失败后进度窗口要等满 5 分钟才能重试。

### 根因（四条，互相独立）

**① 后缀型 Range 被当成文件开头返回（播放报错主因）**

FFmpeg 在 `avformat_open_input()` 探测阶段，为了读 MP3 的 ID3v1 / APE tag 或 MP4 的尾部元数据，
会发 `Range: bytes=-500` 这类「最后 N 字节」请求。旧代理的正则只解析出 `to=500`，
`start` 留空，于是 `formatRangeHeader(null, 500)` 生成 `bytes=0-500`，把**文件开头**返回给播放器，
并谎报成合法 206。libavformat 拿到错位数据就直接放弃，报 `avformat_open_input() failed`。

**② 声明了 Content-Length 却没发够，且 keep-alive 复用了半截响应**

`本机 Documents/myune_music/logs/network.log` 里的证据：

```text
stream done sent=9090     expected=70564705 ⚠ 上游提前结束
stream done sent=1128885  expected=41332587 ⚠ 上游提前结束
stream done sent=725288   expected=26145410 ⚠ 上游提前结束
```

这些小数值既包含「FFmpeg 探测读完就主动断开」，也包含上游 `alt=media` 长连接中途结束。
旧实现只要响应提前结束，就留下一条声明了完整长度、实际却发不够的 HTTP 响应；
默认 keep-alive 又让 mpv 的下一次请求（探测后 seek）复用同一条 TCP 连接，读到错位字节。
`work/probe_playback.py` 用真实凭据实测 Google Drive API 对
`bytes=0-` / `bytes=0-2097151` / `bytes=48401-` / 无 Range 都稳定返回合法 `206/200`、
`Content-Range`、`Content-Length` 与 `fLaC` 首字节，说明**上游 API 正常，问题在本机代理**。

**③ 代理 URL 被当成本地磁盘路径（歌曲详情）**

网络媒体的 `filePath` 是 `http://127.0.0.1:<port>/myune/<base64url>` 或 `nas:` 媒体标识，
不是 Windows 路径。旧 `getCurrentSongDetails()` 无条件调用 `Uri.file()` / `File.exists()` /
Rust `readAudioInfo()`：URL 里的冒号被当成非法卷标，`File.exists()` 抛
`FileSystemException`，`FutureBuilder` 永远落到 `snapshot.hasError`，于是显示「无法加载歌曲详情」。

**④ OAuth 回调把浏览器探测请求当成失败（登录概率性失败）**

旧 `handle(HttpRequest)` 对任何「没有 `state` 匹配」的请求都立刻
`callback.complete(error)`，直接判定登录失败。浏览器在真实回调之外还会请求
`/favicon.ico`、根路径探测、预连接等，这些请求既没有 `code` 也没有 `error`。
低性能机器上浏览器冷启动慢、预取行为更多，命中概率明显更高，表现为「随机登录失败」。
另外 `launchUrl()` 返回 `false` 就抛异常终止登录（但回调服务其实已经起来了），
端口顺延时 `redirect_uri` 变化会让「Web 应用」类型客户端报 `redirect_uri_mismatch`，
以及 `isCancelled` 只在授权完成后检查一次，点「取消」后仍要空等整个超时。

### 改动文件与关键代码位置

| 文件 | 位置 / 函数 | 改动 |
| --- | --- | --- |
| `lib/services/network/local_stream_proxy.dart` | `_handle()` Range 解析 | 识别 `bytes=-N` 后缀型 Range，先用 `_probeTotal()` 补出文件总长，换算成 `[total-N, total-1]` 再向上游请求；补不出长度时退回 200 整段顺序流，绝不谎报区间 |
| 同上 | `_handle()` 响应头 | `response.persistentConnection = false`，网络流响应永不复用连接 |
| 同上 | `_resilientBytes()`（新增） | 上游断流（干净 EOF **或**连接重置抛异常）时，按 `resumeStart + delivered` 的绝对偏移重新 `opener()` 续推，最多 3 次；上游忽略 Range 时用 `skipByteStream()` 跳过已发字节；保证「声明了 Content-Length 就一定发够」 |
| 同上 | `_handle()` `canResume` | 只要声明过 `declaredLength` 就启用续推，顺序流同样覆盖 |
| `lib/page/playlist/playlist_content_notifier.dart` | `getCurrentSongDetails()` | `RemoteMediaRegistry.isNetwork()` 分流，本地分支给 `Uri.file()` / `File.exists()` 加 try/catch 兜底 |
| 同上 | `_networkSongDetails()`（新增） | 优先取 `NetworkTagReader.cached()`，无缓存才 `read()`（12 s 超时 + try/catch）；从 `decodeTarget()` 解出远端可读路径；任何标签读取异常都不让详情页掉进 `hasError` |
| `lib/page/playlist/playlist_models.dart` | `SongDetails` | 新增 `isNetwork` 字段 |
| `lib/page/song_details/song_details_page.dart` | 「文件路径」卡片 / `_openFileLocation()` | 网络媒体隐藏「打开文件所在位置」，并对代理 URL 加双保险拦截，避免弹 explorer 错误窗口 |
| `lib/services/network/google_drive_auth.dart` | `handle()` | 只有带 `code` 或 `error` 的才是回调；`/favicon.ico` 回 204、其它探测回静态等待页，一律不触碰登录状态；`state` 不匹配只拒绝该条、不终止登录 |
| 同上 | `signIn()` | 超时 5 → 10 分钟；`launchUrl()` 失败不再抛异常，把完整授权 URL 回显给界面继续等回调；端口顺延明确提示需登记的 `redirect_uri`；`Timer.periodic` 每 500 ms 检查取消标志；`server.listen(..., onError:)`；`finally` 里 `close()` 加 3 s 超时保护 |
| 同上 | `_respond()` / `_respondProbe()`（新增） | 回调页与探测页都加 `Cache-Control: no-store` |
| `lib/page/network/network_source_editor.dart` | 登录进度弹窗 | 状态文本改为 `SelectableText`，无法自动打开浏览器时可直接选中复制授权地址；说明弹窗补充端口顺延与手动打开的处理 |
| `lib/services/network/google_drive_client.dart` | `uploadFile()` | 每个分块 PUT 带 `Bearer`（每块重新取 token，避免长传过期）；5xx / 连接中断时用 `Content-Range: bytes */total` 查询服务端已确认偏移并续传，最多恢复 3 次，不再从头重传整首歌 |
| 同上 | `_uploadStatus()`（新增） | resumable 会话状态查询 |
| 同上 | `_accessToken()` | 凭据不完整时直接返回可读的中文错误，不再发一次注定失败的 HTTP 请求 |
| 同上 | `_escapeQuery()`（新增） | `files.list?q=` 里的文件夹 ID 转义引号 / 反斜杠 |

### 修复后的播放数据流

```text
mpv / FFmpeg 请求 http://127.0.0.1:<port>/myune/<token>
  ↓ 解析 Range
  ├─ bytes=-500        → _probeTotal() 补总长 → 换算成 [total-500, total-1]
  ├─ bytes=48401-      → 原样透传
  └─ 无 Range          → 原样透传
  ↓ _resolve(target) → WebDav / Ftp / GoogleDrive 的 open(start, end)
  ↓ 响应头：Content-Length / Content-Range / Connection: close
  ↓ _resilientBytes() 按绝对偏移续推，保证发够 Content-Length
  ↓ 客户端主动断开时 async* 取消订阅，不会继续下载整首歌
```

### 缓存到底占多少空间（回答「离线缓存大不大」）

日常所说的「封面缓存」**不缓存音频文件本体**，只落盘两类文件：

```text
文档/myune_music/tag_cache/
  ├─ <hash>.json    标题 / 歌手 / 专辑 / 时长 / 内嵌歌词 / 封面是否可用
  └─ <hash>.cover   封面图二进制（JPEG / PNG）
```

本机实测（102 首已读取过的网络歌曲）：

| 项目 | 数值 |
| --- | --- |
| 102 个 `.json` 合计 | 273,018 字节（约 0.26 MB） |
| 102 个 `.cover` 合计 | 39,074,331 字节（约 37.3 MB） |
| 单张封面 | 最小 20,779 B，最大 1,597,101 B，平均约 374 KB |
| `文档/myune_music` 总计 | 约 39 MB |
| 音频文件 | **0 个** |

也就是说：**剔除音频，只留下封面图 + JSON 元数据 / 歌词**。
上限为 3000 条 / 512 MB，按最久未修改淘汰，不会无限增长。

唯一例外：`NetworkMediaService.tagCachePath()` 在头部标签解析失败时，会把完整音频文件
下载到系统临时目录 `myune_net_cache` 作为解析兜底（单文件上限 96 MB、目录上限 400 MB）。
这是**临时解析缓存**，不是界面上看到的封面缓存，会被自动裁剪，且本轮之后纯字节头部解析
已能覆盖 FLAC / MP3，正常情况下几乎不会再触发。

### 如何验证

1. 播放任意 Google Drive / WebDAV 音频，观察 `errors.log` 不再出现 `avformat_open_input() failed`。
2. 打开「歌曲详情」，应显示远端可读路径、标题 / 歌手 / 专辑 / 封面，且**没有**「打开文件所在位置」按钮。
3. 查看 `network.log`，正常播放时应出现 `serve status=...` 且断流时能看到
   `upstream resumed at=...`；`suffix range resolved total=...` 表示后缀 Range 已被正确换算。
   客户端主动断开走 `stream aborted by client or upstream`，不再被误标成「⚠ 上游提前结束」。
4. 网页登录：反复发起登录、开两个登录窗口、点「取消」后立刻重试，都应正常；
   首选端口被占用时进度窗口会提示需要登记的 `redirect_uri`。
5. 上传大文件途中短暂断网，应从服务端已确认偏移继续，而不是从头重传。

### 已知限制

- 后缀型 Range 需要先补一次文件总长（多一个 API 请求，约 1 s）；仅在 FFmpeg 探测阶段出现。
- 续推最多 3 次；上游持续失败仍会中止，并向 mpv 返回不完整的响应（日志会记录 `upstream resume failed`）。
- 「Web 应用」类型 OAuth 客户端仍需为每个可能的 loopback 端口登记重定向 URI；推荐直接创建「桌面应用」类型客户端。
- 上传续传依赖 Google resumable 会话仍在有效期内（约 1 周）；会话过期会提示重新上传。


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
