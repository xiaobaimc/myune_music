import 'dart:io';

import 'package:path/path.dart' as p;

import '../../page/playlist/playlist_models.dart';
import '../network/remote_entry.dart';
import '../network/remote_media_registry.dart';

/// 一首歌在重复组里的「音质画像」，用于界面展示与自动选优。
class DuplicateCandidate {
  const DuplicateCandidate({
    required this.song,
    required this.extension,
    required this.formatRank,
    required this.sizeBytes,
    required this.lossless,
    required this.qualityLabel,
    required this.sourceLabel,
  });

  final Song song;

  /// 真实扩展名（小写）。网络媒体从代理 URL 里编码的远端文件名解出。
  final String extension;
  final int formatRank;
  final int? sizeBytes;
  final bool lossless;
  final String qualityLabel;
  final String sourceLabel;
}

/// 一组「同一首歌的多个副本」。
class DuplicateGroup {
  const DuplicateGroup({
    required this.key,
    required this.candidates,
    required this.recommendedIndex,
    required this.needsReview,
    required this.reviewReason,
    required this.inferiorIndices,
  });

  /// 由规范化标题 / 专辑拼出的稳定分组键，也是手动选择的持久化 key。
  final String key;
  final List<DuplicateCandidate> candidates;
  final int recommendedIndex;

  /// 相对最佳版本「音质明确更差」的候选下标。自动模式只隐藏这些副本，
  /// 不是每组只留一个：同名同格式、体积又都读不到时，没有任何依据判定
  /// 谁更差，必须整组保留。
  final List<int> inferiorIndices;

  /// 自动模式会保留整组（无法无依据地判定该剔除谁），交给人工确认。
  final bool needsReview;

  /// 需要人工确认的原因，空串表示可以自动判定。
  final String reviewReason;

  String get displayTitle => candidates.first.song.title;
  String get displayAlbum => candidates.first.song.album;

  /// 手动模式：每组只留用户选中的一份时最多隐藏多少副本。
  int get removableCount => candidates.length - 1;

  /// 自动模式：实际会被隐藏的「音质明确更差」的副本数。
  int get autoRemovableCount => inferiorIndices.length;
}

/// 「全部歌曲」的去重判定。
///
/// 判定只看元数据（标题 + 专辑，忽略扩展名和音质标记），不看文件路径，
/// 因此 `xxx.flac` 与 `xxx.mp3` 会归为同一组；同一组里按「无损优先 →
/// 文件更大 → 元数据更完整」挑出要保留的版本，其余从「全部歌曲」虚拟
/// 列表里隐藏。歌单与播放队列持有的是原始路径，不受影响。
class DuplicateResolver {
  DuplicateResolver._();

  /// 只保留数字、小写字母与 CJK / 假名 / 韩文，其余字符统一当分隔符。
  /// 这样 `.` `-` `[` `(` 全角标点都不会把两个副本拆成不同组。
  static final RegExp _nonWord = RegExp(
    '[^0-9a-z\\u4e00-\\u9fff\\u3040-\\u30ff\\uac00-\\ud7af]+',
  );
  static final RegExp _fullWidth = RegExp('[\uff01-\uff5e]');
  static final RegExp _trailingExtension = RegExp(r'\.[a-z0-9]{1,5}$');

  /// 由扩展名 / 音质标记产生的孤立词，不参与分组。
  static const Set<String> _noiseWords = <String>{
    'mp3', 'mp2', 'mp1', 'mpa', 'mpga', 'flac', 'wav', 'wave', 'ape',
    'aac', 'm4a', 'm4b', 'ogg', 'oga', 'opus', 'wv', 'tta', 'tak',
    'alac', 'aiff', 'aif', 'wma', 'dsf', 'dff', 'pcm', 'caf', 'shn',
    '320k', '192k', '128k', '64k', 'hq', 'sq', 'lossless', '24bit',
    '16bit', 'remaster', '无损', '高音质', '标准音质',
  };

  static const Set<String> _losslessFormats = <String>{
    'flac', 'wav', 'wave', 'pcm', 'aiff', 'aif', 'aifc', 'ape', 'wv',
    'wavpack', 'tta', 'tak', 'alac', 'shn', 'shorten', 'dsf', 'dff',
    'dsd', 'caf', 'au', 'snd', 'voc', 'iff', '8svx',
  };

  static const Set<String> _highQualityFormats = <String>{
    'ogg', 'oga', 'opus', 'aac', 'adts', 'm4a', 'm4b', 'm4r', 'mka',
    'mp4a', 'aax', 'aa', 'spx', 'celt', 'ac3', 'eac3', 'dts', 'dtshd',
    'mlp', 'thd', 'truehd', 'ac4',
  };

  static const Set<String> _lossyFormats = <String>{
    'mp3', 'mp2', 'mp1', 'mpa', 'mpga', 'm1a', 'm2a', 'wma', 'asf',
    'mpc', 'mp+', 'vqf', 'ra', 'ram', 'amr', '3ga', 'gsm', 'adpcm',
  };

  /// 把标题 / 专辑规范化成可比较的形式：小写、去扩展名、去音质标记、
  /// 去标点、合并空白、全角转半角。
  static String normalizeText(String input) {
    var text = input.toLowerCase().trim();
    text = text.replaceAll(_trailingExtension, '');
    text = text.replaceAllMapped(_fullWidth, (match) {
      final code = match.group(0)!.codeUnitAt(0);
      return String.fromCharCode(code - 0xfee0);
    });
    text = text.replaceAll(_nonWord, ' ');
    final words = text
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty && !_noiseWords.contains(word))
        .toList();
    return words.join(' ');
  }

  /// 一首歌的「身份」：网络媒体用代理 token 里的媒体 ID（不含端口），
  /// 本地文件用路径。用于先合并完全相同的条目，避免同一路径被多个歌单
  /// 引用、或本机代理端口漂移后，在「全部歌曲」里出现两条一模一样的记录。
  static String identityOf(String filePath) {
    final mediaId = RemoteMediaRegistry.mediaIdOf(filePath);
    if (mediaId != null && mediaId.isNotEmpty) return 'media:$mediaId';
    return 'path:$filePath';
  }

  /// 分组键：标题 + 专辑。歌手不进键（很多副本的歌手字段缺失或写法不同），
  /// 但会在 [DuplicateGroup.needsReview] 里作为「需人工确认」的信号。
  static String keyOf(Song song) {
    var title = normalizeText(song.title);
    if (title.isEmpty || title == '未知歌曲' || title == 'unknown') {
      title = normalizeText(_nameOf(song.filePath));
    }
    final album = normalizeText(song.album);
    final parts = <String>[title];
    if (album.isNotEmpty && album != '未知专辑' && album != 'unknown') {
      parts.add(album);
    }
    return parts.join('|');
  }

  /// 找出所有重复组，并按「推荐保留项」排序好组内候选。
  /// 传入的必须是**未去重**的全量歌曲（来自各歌单的原始路径）。
  static List<DuplicateGroup> findGroups(List<Song> songs) {
    final buckets = <String, List<Song>>{};
    final identities = <String>{};
    for (final song in songs) {
      // 同一个文件的两个代理 URL 不算重复曲目，对话框里不展示这种噪声。
      if (!identities.add(identityOf(song.filePath))) continue;
      buckets.putIfAbsent(keyOf(song), () => <Song>[]).add(song);
    }

    final groups = <DuplicateGroup>[];
    for (final entry in buckets.entries) {
      if (entry.value.length < 2) continue;
      final candidates = entry.value.map(candidateOf).toList(growable: false);
      final artistsMismatch = artistsDiffer(candidates);
      final inferior = inferiorIndices(candidates);
      final tieQuality = inferior.isEmpty;
      groups.add(
        DuplicateGroup(
          key: entry.key,
          candidates: candidates,
          recommendedIndex: bestIndex(candidates),
          inferiorIndices: inferior,
          needsReview: artistsMismatch || tieQuality,
          reviewReason: artistsMismatch
              ? '歌手不一致'
              : tieQuality
                  ? '音质相同'
                  : '',
        ),
      );
    }
    // 把「自动模式能直接处理」的组排前面，需人工确认的组排后面。
    groups.sort((a, b) {
      final byAuto = b.autoRemovableCount.compareTo(a.autoRemovableCount);
      return byAuto != 0
          ? byAuto
          : b.removableCount.compareTo(a.removableCount);
    });
    return groups;
  }

  /// 按分组选出要保留的歌曲，并保持 [ordered] 的原始顺序。
  /// [overrides] 是用户手动指定的「分组键 → 要保留的 filePath」，优先于自动选优。
  static List<Song> resolve(
    List<Song> ordered,
    Map<String, String> overrides,
  ) {
    if (ordered.isEmpty) return <Song>[];

    // 先按身份合并完全相同的一份，保持首次出现的顺序。旧实现用
    // artist|title|album 去重时也隐含保证了这一点，不能因为新的音质判定
    // 在「无法判定」时保留整组，反而把同一首歌显示两遍。
    final identities = <String>{};
    final songs = <Song>[];
    for (final song in ordered) {
      if (identities.add(identityOf(song.filePath))) songs.add(song);
    }

    final buckets = <String, List<int>>{};
    for (var i = 0; i < songs.length; i++) {
      buckets.putIfAbsent(keyOf(songs[i]), () => <int>[]).add(i);
    }

    final keep = <int>{};
    for (final entry in buckets.entries) {
      final indices = entry.value;
      if (indices.length == 1) {
        keep.add(indices.first);
        continue;
      }

      // 用户手动指定过保留项时直接尊重选择，这一组只留选中的那一份。
      final override = overrides[entry.key];
      if (override != null && override.isNotEmpty) {
        final picked = indices.indexWhere(
          (i) => songs[i].filePath == override,
        );
        if (picked >= 0) {
          keep.add(indices[picked]);
          continue;
        }
        // override 指向的路径已经不在库里（文件被删 / 歌单被清空），
        // 忽略这条过期记录，回退到自动判定。
      }

      final candidates = indices
          .map((i) => candidateOf(songs[i]))
          .toList(growable: false);
      // 同名但歌手不一致时，自动模式不剔除任何一份：很可能是翻唱 /
      // 不同演绎而非同一录音的不同格式。
      if (artistsDiffer(candidates)) {
        keep.addAll(indices);
        continue;
      }
      // 只隐藏「音质明确更差」的副本，而不是每组只留一个。
      // 两份同名同格式、体积也一样（或都读不到体积）的文件，可能是同一
      // 份转录放在了不同目录，没有依据说谁更差；此时整组保留，等用户在
      // 去重对话框里手动决定。
      final inferior = inferiorIndices(candidates).toSet();
      if (inferior.isEmpty) {
        keep.addAll(indices);
        continue;
      }
      for (var j = 0; j < indices.length; j++) {
        if (!inferior.contains(j)) keep.add(indices[j]);
      }
    }

    return <Song>[
      for (var i = 0; i < songs.length; i++)
        if (keep.contains(i)) songs[i],
    ];
  }

  /// 生成一首歌的音质画像。本地文件读实际大小，网络媒体没有本地大小，
  /// 只能按格式等级 + 元数据完整度比较（界面会明确标注「网络媒体」）。
  static DuplicateCandidate candidateOf(Song song) {
    final name = _nameOf(song.filePath);
    var extension = RemoteEntry.extensionOf(name);
    if (extension.isEmpty) extension = RemoteEntry.extensionOf(song.title);

    final lossless = _losslessFormats.contains(extension);
    final rank = lossless
        ? 4
        : _highQualityFormats.contains(extension)
            ? 3
            : _lossyFormats.contains(extension)
                ? 2
                : 1;

    final network = RemoteMediaRegistry.isNetwork(song.filePath) ||
        song.filePath.contains('://');
    int? size;
    if (!network) {
      try {
        final file = File(song.filePath);
        if (file.existsSync()) size = file.statSync().size;
      } catch (_) {
        size = null;
      }
    }

    final formatLabel = extension.isEmpty ? '未知格式' : extension.toUpperCase();
    final tierLabel = lossless ? '无损' : rank >= 3 ? '高码率有损' : '有损';
    final sizeLabel = size == null ? '网络媒体' : _humanSize(size);
    return DuplicateCandidate(
      song: song,
      extension: extension,
      formatRank: rank,
      sizeBytes: size,
      lossless: lossless,
      qualityLabel: '$formatLabel · $tierLabel · $sizeLabel',
      sourceLabel: network ? '云端' : '本地',
    );
  }

  /// 组内歌手是否明显不一致（用于避免把翻唱 / 不同演绎误判为重复）。
  /// 缺失歌手（未知歌手 / 空）不参与判断，避免元数据不全导致误报。
  static bool artistsDiffer(List<DuplicateCandidate> candidates) {
    final artists = <String>{};
    for (final candidate in candidates) {
      final artist = normalizeText(candidate.song.artist);
      if (artist.isNotEmpty && artist != '未知歌手' && artist != 'unknown') {
        artists.add(artist);
      }
    }
    return artists.length > 1;
  }

  /// 返回相对最佳版本「音质明确更差」的候选下标。
  ///
  /// 只比较真正的音质维度（格式等级 + 文件体积），不把「有时长 / 有封面 /
  /// 路径字典序」这类平局打破条件当成剔除理由：同名同格式、体积又都读不到
  /// 时无法证明哪份更差，必须整组保留。网络媒体没有本地体积，所以「本地
  /// FLAC 30 MB」和「云端 FLAC 体积未知」也不会被判定为谁更差。
  ///
  /// 同格式时要求体积差距至少 1%：差几个字节通常只是同一份转录被重新封
  /// 装，不是「音质更烂」；而 320 kbps 与 128 kbps 同名副本通常差 60% 以上，
  /// 会被正常剔除。
  static List<int> inferiorIndices(List<DuplicateCandidate> candidates) {
    if (candidates.length < 2) return <int>[];
    final best = candidates[bestIndex(candidates)];
    final result = <int>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      if (candidate.formatRank < best.formatRank) {
        result.add(i);
        continue;
      }
      if (candidate.formatRank != best.formatRank) continue;
      final size = candidate.sizeBytes;
      final bestSize = best.sizeBytes;
      // 任一方体积未知就不判定，避免把网络媒体误当成劣质副本。
      if (size == null || bestSize == null || bestSize <= 0) continue;
      final diff = bestSize - size;
      // diff * 100 >= bestSize 等价于「差距 >= 1%」，用整数避免浮点误差。
      if (diff > 0 && diff * 100 >= bestSize) result.add(i);
    }
    return result;
  }

  /// 返回音质最好的候选下标。比较顺序：
  /// 格式等级 → 文件体积 → 有时长 → 有封面 → 路径字典序（保证结果稳定）。
  static int bestIndex(List<DuplicateCandidate> candidates) {
    var best = 0;
    for (var i = 1; i < candidates.length; i++) {
      if (_better(candidates[i], candidates[best])) best = i;
    }
    return best;
  }

  static bool _better(DuplicateCandidate a, DuplicateCandidate b) {
    if (a.formatRank != b.formatRank) return a.formatRank > b.formatRank;
    final sizeA = a.sizeBytes ?? -1;
    final sizeB = b.sizeBytes ?? -1;
    if (sizeA != sizeB) return sizeA > sizeB;
    final durationA = a.song.duration != null ? 1 : 0;
    final durationB = b.song.duration != null ? 1 : 0;
    if (durationA != durationB) return durationA > durationB;
    final artA = a.song.albumArt != null ? 1 : 0;
    final artB = b.song.albumArt != null ? 1 : 0;
    if (artA != artB) return artA > artB;
    return a.song.filePath.compareTo(b.song.filePath) < 0;
  }

  /// 网络媒体的 filePath 是代理 URL，真实文件名编码在 token 的 `p` 字段里。
  static String _nameOf(String filePath) {
    if (RemoteMediaRegistry.isNetwork(filePath) || filePath.contains('://')) {
      final target = RemoteMediaRegistry.decodeTarget(filePath);
      final remote = target?['p']?.toString() ?? '';
      if (remote.isNotEmpty) {
        final name = _basename(remote);
        if (name.isNotEmpty) {
          try {
            return Uri.decodeComponent(name);
          } catch (_) {
            return name;
          }
        }
      }
      final title = target?['t']?.toString() ?? '';
      if (title.isNotEmpty) return title;
      return filePath;
    }
    return p.basename(filePath);
  }

  static String _basename(String value) {
    final slash = value.lastIndexOf('/');
    final backslash = value.lastIndexOf('\\');
    final index = slash > backslash ? slash : backslash;
    return index < 0 ? value : value.substring(index + 1);
  }

  static String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
