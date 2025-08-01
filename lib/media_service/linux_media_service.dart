import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:anni_mpris_service/anni_mpris_service.dart';
import 'platform_media_service.dart';
import 'dart:typed_data';

class _MyMPRISService extends MPRISService {
  //添加Callback后缀以避免与父类方法重名
  final Future<void> Function()? onPlayCallback;
  final Future<void> Function()? onPauseCallback;
  final Future<void> Function()? onNextCallback;
  final Future<void> Function()? onPreviousCallback;
  final Future<void> Function(Duration) onSeekCallback;
  final Future<void> Function(String, Duration) onSetPositionCallback;

  _MyMPRISService({
    this.onPlayCallback,
    this.onPauseCallback,
    this.onNextCallback,
    this.onPreviousCallback,
    required this.onSeekCallback,
    required this.onSetPositionCallback,
  }) : super(
         'myune_music',
         identity: 'MyUne Music',
         desktopEntry: 'myune-music',
         canGoNext: true,
         canGoPrevious: true,
         canPlay: true,
         canPause: true,
         canSeek: true,
         supportLoopStatus: true,
       );

  @override
  Future<void> onNext() async => await onNextCallback?.call();

  @override
  Future<void> onPause() async => await onPauseCallback?.call();

  @override
  Future<void> onPlay() async => await onPlayCallback?.call();

  @override
  Future<void> onPlayPause() async {
    if (playbackStatus == PlaybackStatus.playing) {
      await onPauseCallback?.call();
    } else {
      await onPlayCallback?.call();
    }
  }

  @override
  Future<void> onPrevious() async => await onPreviousCallback?.call();

  @override
  Future<void> onSeek(int offsetInUs) async {
    // position 是父类提供的当前位置
    final newPosition = position + Duration(microseconds: offsetInUs);
    await onSeekCallback(newPosition);
  }

  @override
  Future<void> onSetPosition(String trackId, int positionInUs) async {
    await onSetPositionCallback(trackId, Duration(microseconds: positionInUs));
  }
}

class LinuxMediaService implements PlatformMediaService {
  final _MyMPRISService _mpris;
  int _trackIdCounter = 0;
  String? _currentArtFilePath; // 存储当前封面文件路径

  LinuxMediaService({
    Future<void> Function()? onPlay,
    Future<void> Function()? onPause,
    Future<void> Function()? onNext,
    Future<void> Function()? onPrevious,
    required Future<void> Function(Duration) onSeek,
    required Future<void> Function(String, Duration) onSetPosition,
  }) : _mpris = _MyMPRISService(
         // 将回调传递给重命名后的参数
         onPlayCallback: onPlay,
         onPauseCallback: onPause,
         onNextCallback: onNext,
         onPreviousCallback: onPrevious,
         onSeekCallback: onSeek,
         onSetPositionCallback: onSetPosition,
       );

  @override
  Future<void> updateMetadata({
    required String title,
    required String artist,
    String? album,
    Uint8List? albumArt,
  }) async {
    _trackIdCounter++;
    final trackId = '/org/mpris/MediaPlayer2/track/$_trackIdCounter';

    String? artUrl;
    String? newArtFilePath; // 用来存储新文件的路径

    if (albumArt != null && albumArt.isNotEmpty) {
      try {
        // 1. 获取临时目录
        final tempDir = await getTemporaryDirectory();
        // 2. 创建一个临时文件
        final fileName = 'myune_album_art_$_trackIdCounter.png';
        final artFile = File(p.join(tempDir.path, fileName));
        // 3. 将图片数据写入文件
        newArtFilePath = artFile.path; // 记录新文件路径
        await artFile.writeAsBytes(albumArt);
        // 4. 生成 file:// URI
        artUrl = artFile.uri.toString();
      } catch (e) {
        artUrl = null; // 如果失败，则不显示封面
        newArtFilePath = null;
      }
    }

    // 在设置新元数据之前，删除旧文件
    try {
      // 如果 _currentArtFilePath 存在 (不是第一次) 并且与新路径不同
      if (_currentArtFilePath != null &&
          _currentArtFilePath != newArtFilePath) {
        final oldArtFile = File(_currentArtFilePath!);
        if (await oldArtFile.exists()) {
          await oldArtFile.delete();
        }
      }
    } catch (e) {
      // 忽略错误
    }

    // 更新当前的封面路径为新的路径
    _currentArtFilePath = newArtFilePath;

    _mpris.metadata = Metadata(
      trackId: trackId,
      trackTitle: title,
      trackArtist: [artist],
      albumName: album,
      artUrl: artUrl,
    );
  }

  @override
  Future<void> updateState(bool isPlaying) async {
    _mpris.playbackStatus = isPlaying
        ? PlaybackStatus.playing
        : PlaybackStatus.paused;
  }

  @override
  Future<void> updateTimeline({
    required Duration position,
    required Duration duration,
  }) async {
    // 单独更新位置
    _mpris.updatePosition(position);

    // 只有在时长变化时才更新，以避免不必要的 D-Bus 调用
    if (_mpris.metadata.trackLength != duration) {
      final newMetadata = _mpris.metadata.copyWith(trackLength: duration);
      _mpris.metadata = newMetadata;
    }
  }

  @override
  Future<void> dispose() async {
    await _mpris.dispose();
  }
}
