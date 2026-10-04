import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../page/playlist/playlist_content_notifier.dart';

class SongCoverBuilder extends StatefulWidget {
  final String filePath;
  final Widget Function(BuildContext context, Uint8List? cover) builder;

  const SongCoverBuilder({
    super.key,
    required this.filePath,
    required this.builder,
  });

  @override
  State<SongCoverBuilder> createState() => _SongCoverBuilderState();
}

class _SongCoverBuilderState extends State<SongCoverBuilder> {
  late PlaylistContentNotifier _notifier;
  String? _coverKey;
  Uint8List? _cover;
  bool _requestScheduled = false;

  @override
  void initState() {
    super.initState();
    _notifier = context.read<PlaylistContentNotifier>();
    _attach(widget.filePath);
    _scheduleRequest();
  }

  @override
  void didUpdateWidget(covariant SongCoverBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _detach();
      _attach(widget.filePath);
      _scheduleRequest();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _attach(String filePath) {
    final key = _notifier.coverCacheKey(filePath);
    _coverKey = key;
    _cover = _notifier.coverOfCacheKey(key);
    _notifier.coverStore.addPathListener(key, _handleCoverChanged);
  }

  void _detach() {
    final key = _coverKey;
    if (key == null) {
      return;
    }
    _notifier.coverStore.removePathListener(key, _handleCoverChanged);
    _notifier.releaseSongCover(key);
    _coverKey = null;
  }

  void _handleCoverChanged() {
    final key = _coverKey;
    if (!mounted || key == null) {
      return;
    }
    final next = _notifier.coverOfCacheKey(key);
    if (identical(next, _cover)) {
      return;
    }
    setState(() => _cover = next);
  }

  // 把请求推迟到当前帧结束之后，避免在 build 阶段触发
  void _scheduleRequest() {
    if (_requestScheduled) {
      return;
    }
    _requestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestScheduled = false;
      _requestWhenIdle();
    });
  }

  void _requestWhenIdle() {
    if (!mounted) {
      return;
    }
    final key = _coverKey;
    if (key == null) {
      return;
    }

    // 快速滚动时先不读封面，贴到下一帧再判断
    // 速度降下来之后会补上，滑动过程中不堆积磁盘读取
    // issue #127
    if (Scrollable.recommendDeferredLoadingForContext(context)) {
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        scheduleMicrotask(_requestWhenIdle);
      });
      return;
    }

    _notifier.requestSongCover(key);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _cover);
}
