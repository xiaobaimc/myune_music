/// 网络硬盘 / 共享网盘上的一个目录项。
///
/// [path] 对 WebDAV 是服务端返回的 href（已解析成绝对 URL，可直接用于
/// 二次请求），对 FTP 是 POSIX 风格的绝对路径。两种协议统一成同一模型，
/// 页面层不需要区分。
class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.modified,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final DateTime? modified;

  /// 常见与老旧音频格式。用扩展名集合而非正则，避免 `mp+`、`.m4a/.m4v`
  /// 这类带正则元字符或前缀重叠的扩展名被误判。
  ///
  /// 覆盖：MPEG 层 1/2/3、无损（FLAC/APE/WavPack/TTA/TAK/Shorten/DSD）、
  /// PCM/AIFF/AU/CAF、AAC/ALAC/MP4 音频、Ogg 家族、WMA/ASF、老式模块音乐、
  /// MIDI、AMR/RealAudio、AC3/DTS/E-AC3 等。
  static const Set<String> audioExtensions = <String>{
    'mp3', 'mp2', 'mp1', 'mpa', 'mpga', 'm1a', 'm2a', 'mp4a',
    'flac', 'wav', 'wave', 'pcm', 'aiff', 'aif', 'aifc', 'au', 'snd',
    'caf', 'voc', 'iff', '8svx', 'adpcm', 'g722', 'gsm', 'cdda',
    'm4a', 'm4b', 'm4r', 'aac', 'adts', 'alac', 'aax', 'aa',
    'ogg', 'oga', 'opus', 'spx', 'celt', 'mka',
    'wma', 'asf', 'ape', 'tak', 'tta', 'wv', 'wavpack', 'shn', 'shorten',
    'dsf', 'dff', 'dsd', 'mpc', 'mp+', 'vqf', 'ra', 'ram', 'amr', '3ga',
    'mid', 'midi', 'kar', 'rmi', 'mod', 'xm', 'it', 's3m', 'umx', 'mtm',
    'ac3', 'eac3', 'dts', 'dtshd', 'mlp', 'thd', 'truehd', 'ac4',
  };

  /// 常见视频容器。识别它们有两个用途：
  /// 1. 文件列表里明确排除，避免网盘中的视频混入音乐列表；
  /// 2. 播放链路仍把它们当作「仅音频播放」的媒体（mpv 无视频输出时只出声），
  ///    因此代理会给出正确的 video/* Content-Type。
  static const Set<String> videoExtensions = <String>{
    'mp4', 'm4v', 'mov', 'mkv', 'avi', 'wmv', 'flv', 'f4v', 'webm',
    'mpg', 'mpeg', 'mpe', 'm2v', 'ts', 'm2ts', 'mts', 'vob',
    '3gp', '3g2', 'rm', 'rmvb', 'ogv', 'ogm', 'divx', 'xvid',
    'hevc', 'h265', 'h264', 'm4p', 'qt', 'mxf', 'dav',
  };

  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot >= name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase().trim();
  }

  static bool isAudioName(String name) =>
      audioExtensions.contains(extensionOf(name));

  static bool isVideoName(String name) =>
      videoExtensions.contains(extensionOf(name));

  bool get isAudio => !isDirectory && isAudioName(name);

  bool get isVideo => !isDirectory && isVideoName(name);

  /// 是否可由播放器打开（视频容器按「仅音频」处理）。
  bool get isPlayableMedia => isAudio || isVideo;

  String get sizeLabel {
    final bytes = size;
    if (bytes == null || bytes < 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
