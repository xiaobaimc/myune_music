import 'package:flutter/material.dart';
import 'package:flutter_web_scroll/flutter_web_scroll.dart';
import 'dart:async';
import '../services/font_service.dart';

class FontSelectorDialog extends StatefulWidget {
  final String currentFontFamily;

  const FontSelectorDialog({
    super.key,
    required this.currentFontFamily,
  });

  @override
  State<FontSelectorDialog> createState() => _FontSelectorDialogState();
}

class _FontSelectorDialogState extends State<FontSelectorDialog> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _fontService = FontService();

  List<FontMeta> _allFonts = [];
  Map<String, FontMeta> _fontsMap = {};
  List<FontMeta> _filteredFonts = [];
  String? _selectedFont;
  FontMeta? _selectedMeta;
  String? _previewFont;
  bool _isScanning = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selectedFont = widget.currentFontFamily;

    _searchController.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), _applyFilter);
    });

    _initFonts();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

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

  Future<void> _selectFont(FontMeta meta) async {
    setState(() {
      _selectedFont = meta.fileName;
      _selectedMeta = meta;
      _previewFont = meta.fileName;
    });

    if (meta.fileName != 'Misans' && !meta.isLoaded) {
      await _fontService.loadFont(meta);
    }
    if (!mounted) return;
    setState(() {});
  }

  void _resetToDefault() {
    _selectFont(_fontService.defaultFontMeta);
  }

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
        width: 460,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSearchBar(context),
            const SizedBox(height: 8),
            _buildPreviewArea(context),
            const SizedBox(height: 8),
            Expanded(child: _buildFontList(context)),
          ],
        ),
      ),
      actions: _buildActions(context),
    );
  }

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

  Future<void> _refreshFonts() async {
    setState(() => _isScanning = true);
    await _fontService.rescan();
    await _initFonts();
  }

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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildPreviewArea(BuildContext context) {
    final previewFamily = _previewFontFamily();
    final displayName = _selectedMeta?.displayName ??
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
            '字体预览效果 — The quick brown fox jumps over the lazy dog.',
            style: TextStyle(
              fontFamily: previewFamily,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

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

    return SmoothScrollWeb(
      controller: _scrollController,
      config: SmoothScrollConfig.lenis(),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _filteredFonts.length,
        itemBuilder: (context, index) {
          final meta = _filteredFonts[index];
          final isSelected = meta.fileName == _selectedFont;

          return _buildFontTile(context, meta, isSelected);
        },
      ),
    );
  }

  Widget _buildFontTile(BuildContext context, FontMeta meta, bool isSelected) {
    final fontFamily = meta.fileName == 'Misans' ? null : meta.fileName;

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
          fontFamily: fontFamily,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _selectFont(meta),
    );
  }

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
