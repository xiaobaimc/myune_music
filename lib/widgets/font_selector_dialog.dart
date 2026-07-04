import 'package:flutter/material.dart';
import 'package:silky_scroll/silky_scroll.dart';
import '../theme/scroll_config.dart';
import 'dart:async';
import '../services/font_service.dart';

/// 字体选择对话框，用于浏览和选择系统字体
/// 用户可以选择字体并确认，对话框返回所选字体的文件名。
class FontSelectorDialog extends StatefulWidget {
  /// 当前已选中的字体家族名称
  final String currentFontFamily;

  const FontSelectorDialog({super.key, required this.currentFontFamily});

  @override
  State<FontSelectorDialog> createState() => _FontSelectorDialogState();
}

class _FontSelectorDialogState extends State<FontSelectorDialog> {
  /// 搜索框的文本控制器
  final _searchController = TextEditingController();

  /// 字体列表的滚动控制器
  final _scrollController = ScrollController();

  /// 字体服务实例，用于扫描和加载字体
  final _fontService = FontService();

  /// 所有已扫描字体的完整列表
  List<FontMeta> _allFonts = [];

  /// 字体文件名到元数据的映射表
  Map<String, FontMeta> _fontsMap = {};

  /// 搜索过滤后的字体列表
  List<FontMeta> _filteredFonts = [];

  /// 当前选中的字体文件名
  String? _selectedFont;

  /// 当前选中的字体元数据
  FontMeta? _selectedMeta;

  /// 预览用字体文件名
  String? _previewFont;

  /// 是否正在扫描字体
  bool _isScanning = true;

  /// 搜索防抖定时器
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // 初始化当前选中的字体
    _selectedFont = widget.currentFontFamily;

    // 设置搜索框文本变化监听器，使用250ms防抖
    _searchController.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), _applyFilter);
    });

    // 初始化字体列表
    _initFonts();
  }

  @override
  void dispose() {
    // 取消防抖定时器
    _debounce?.cancel();
    // 释放控制器资源
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 初始化字体列表
  ///
  /// 扫描系统字体，合并默认字体，然后按显示名称排序
  Future<void> _initFonts() async {
    final scanned = await _fontService.scanFonts();

    final defaultMeta = _fontService.defaultFontMeta;

    final existingFonts = <String>{};
    final mergedFonts = <FontMeta>[defaultMeta];
    final fontsMap = <String, FontMeta>{defaultMeta.fileName: defaultMeta};

    for (final meta in scanned) {
      if (existingFonts.add(meta.fileName)) {
        mergedFonts.add(meta);
        fontsMap[meta.fileName] = meta;
      }
    }

    mergedFonts.sort((a, b) {
      if (a.fileName == defaultMeta.fileName) return -1;
      if (b.fileName == defaultMeta.fileName) return 1;
      return a.displayName.compareTo(b.displayName);
    });

    _allFonts = mergedFonts;
    _fontsMap = fontsMap;
    _filteredFonts = mergedFonts;
    _selectedMeta = _fontsMap[_selectedFont];
    if (!mounted) return;
    setState(() => _isScanning = false);
  }

  /// 根据搜索关键词过滤字体列表
  ///
  /// 匹配显示名称或文件名，不区分大小写
  void _applyFilter() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredFonts = _allFonts;
      } else {
        _filteredFonts = _allFonts.where((f) {
          return f.displayName.toLowerCase().contains(query) ||
              f.fileName.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  /// 选择指定字体并加载预览
  ///
  /// 更新选中状态，如果字体未加载则立即加载
  Future<void> _selectFont(FontMeta meta) async {
    setState(() {
      _selectedFont = meta.fileName;
      _selectedMeta = meta;
      _previewFont = meta.fileName;
    });

    if (meta.fileName != 'Misans' && !meta.isLoaded) {
      await _fontService.loadFont(meta);
      if (!mounted) return;
      setState(() {});
    }
  }

  /// 重置为默认字体
  void _resetToDefault() {
    _selectFont(_fontService.defaultFontMeta);
  }

  /// 获取当前预览使用的字体家族名称
  ///
  /// 优先级：预览字体 > 选中字体 > 默认字体
  String _previewFontFamily() {
    if (_previewFont != null && _previewFont != 'Misans') {
      return _previewFont!;
    }
    if (_selectedFont != null && _selectedFont != 'Misans') {
      return _selectedFont!;
    }
    return _selectedFont ?? 'Misans';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _buildTitle(context),
      content: SizedBox(
        width: 520,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 搜索栏
            _buildSearchBar(context),
            const SizedBox(height: 8),
            // 字体预览区
            _buildPreviewArea(context),
            const SizedBox(height: 8),
            // 字体列表
            Expanded(child: _buildFontList(context)),
          ],
        ),
      ),
      actions: _buildActions(context),
    );
  }

  /// 构建对话框标题栏
  ///
  /// 包含标题、刷新按钮和重置默认字体按钮
  Widget _buildTitle(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('选择字体'),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: _isScanning ? null : _refreshFonts,
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '刷新字体列表',
            ),
            TextButton.icon(
              onPressed: _resetToDefault,
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('默认字体'),
            ),
          ],
        ),
      ],
    );
  }

  /// 刷新系统字体列表
  ///
  /// 重新扫描字体目录，更新字体列表
  Future<void> _refreshFonts() async {
    setState(() => _isScanning = true);
    await _fontService.rescan();
    await _initFonts();
  }

  /// 构建搜索栏组件
  ///
  /// 包含搜索图标、文本输入框和清除按钮
  Widget _buildSearchBar(BuildContext context) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: '搜索字体...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _searchController.clear();
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// 构建字体预览区域
  ///
  /// 显示当前选中的字体名称和预览示例文字
  Widget _buildPreviewArea(BuildContext context) {
    final previewFamily = _previewFontFamily();
    final displayName =
        _selectedMeta?.displayName ??
        _fontService.resolveDisplayName(_selectedFont ?? 'Misans');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前选中: $displayName',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '字体预览效果\nThe quick brown fox jumps over the lazy dog.\n放て！心に刻んだ夢を 未来さえ置き去りにして。',
            style: TextStyle(fontFamily: previewFamily, fontSize: 16),
          ),
        ],
      ),
    );
  }

  /// 构建字体列表组件
  ///
  /// 使用平滑滚动容器包裹ListView，
  /// 扫描中显示加载指示器，无结果时显示空状态提示
  Widget _buildFontList(BuildContext context) {
    if (_isScanning) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredFonts.isEmpty) {
      return Center(
        child: Text(
          '未找到匹配的字体',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return SilkyScroll(
      controller: _scrollController,
      silkyScrollDuration: ScrollConfig.duration,
      scrollSpeed: ScrollConfig.speed,
      animationCurve: ScrollConfig.curve,
      builder: (context, controller, physics, _) => ListView.builder(
        controller: controller,
        physics: physics,
        itemCount: _filteredFonts.length,
        itemBuilder: (context, index) {
          final meta = _filteredFonts[index];
          final isSelected = meta.fileName == _selectedFont;

          return _buildFontTile(context, meta, isSelected);
        },
      ),
    );
  }

  /// 构建单个字体列表项
  ///
  /// 显示字体名称，选中时高亮显示
  Widget _buildFontTile(BuildContext context, FontMeta meta, bool isSelected) {
    return ListTile(
      dense: true,
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 20,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(
        meta.displayName,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected ? Theme.of(context).colorScheme.primary : null,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _selectFont(meta),
    );
  }

  /// 构建对话框操作按钮
  ///
  /// 包含取消和确定按钮
  List<Widget> _buildActions(BuildContext context) {
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () {
          Navigator.of(context).pop(_selectedFont);
        },
        child: const Text('确定'),
      ),
    ];
  }
}
