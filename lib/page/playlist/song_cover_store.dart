import 'package:flutter/foundation.dart';

class SongCoverStore extends ChangeNotifier {
  final Map<String, Uint8List> _covers = {};

  final Map<String, Set<VoidCallback>> _pathListeners = {};

  bool contains(String cacheKey) => _covers.containsKey(cacheKey);

  Uint8List? coverOf(String cacheKey) => _covers[cacheKey];

  int get length => _covers.length;

  Iterable<String> get keys => _covers.keys;

  // 写入封面数据 数据没有真正变化时返回 false 并且不触发任何通知
  bool put(String cacheKey, Uint8List bytes) {
    if (identical(_covers[cacheKey], bytes)) {
      return false;
    }
    _covers[cacheKey] = bytes;
    _notifyKey(cacheKey);
    return true;
  }

  // 丢弃某个路径的封面（缓存淘汰用）整条记录会被删除
  bool remove(String cacheKey) {
    if (_covers.remove(cacheKey) == null) {
      return false;
    }
    _notifyKey(cacheKey);
    return true;
  }

  // 清空全部封面数据
  void clear() {
    if (_covers.isEmpty) {
      return;
    }
    final keys = _covers.keys.toList(growable: false);
    _covers.clear();
    for (final key in keys) {
      _notifyKey(key);
    }
  }

  void addPathListener(String cacheKey, VoidCallback listener) {
    (_pathListeners[cacheKey] ??= <VoidCallback>{}).add(listener);
  }

  void removePathListener(String cacheKey, VoidCallback listener) {
    final listeners = _pathListeners[cacheKey];
    if (listeners == null) {
      return;
    }
    listeners.remove(listener);
    if (listeners.isEmpty) {
      _pathListeners.remove(cacheKey);
    }
  }

  void _notifyKey(String cacheKey) {
    final listeners = _pathListeners[cacheKey];
    if (listeners != null && listeners.isNotEmpty) {
      // 复制一份，避免回调里增删订阅导致并发修改
      for (final listener in List<VoidCallback>.of(listeners)) {
        listener();
      }
    }
    // 全局订阅者（歌手/专辑头图等）需要感知封面变化
    notifyListeners();
  }
}
