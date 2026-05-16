import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_fonts/system_fonts.dart';

/// 字体元数据类，用于存储单个字体的基本信息
class FontMeta {
  /// 字体文件名
  final String fileName;

  /// 字体家族名称
  final String fontFamily;

  /// 用于界面显示的友好名称
  final String displayName;

  /// 字体文件在系统中的完整路径
  final String filePath;

  /// 标记字体是否已被加载到内存中
  bool isLoaded;

  /// 创建一个字体元数据实例
  ///
  /// [fileName] 字体文件名
  /// [fontFamily] 字体家族名称
  /// [displayName] 显示名称
  /// [filePath] 字体文件路径
  /// [isLoaded] 是否已加载，默认false
  FontMeta({
    required this.fileName,
    required this.fontFamily,
    required this.displayName,
    required this.filePath,
    this.isLoaded = false,
  });

  /// 将字体元数据转换为JSON格式，用于缓存
  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'fontFamily': fontFamily,
    'displayName': displayName,
    'filePath': filePath,
  };

  /// 将JSON对象转换回FontMeta实例，用于从缓存恢复
  factory FontMeta.fromJson(Map<String, dynamic> json) => FontMeta(
    fileName: json['fileName'] as String,
    fontFamily: json['fontFamily'] as String,
    displayName: json['displayName'] as String,
    filePath: json['filePath'] as String,
  );
}

/// 字体服务类，负责系统字体的扫描、加载和管理
///
/// 采用单例模式设计，通过 [FontService()] 获取实例
/// 主要功能包括：
/// - 扫描系统字体目录获取可用字体
/// - 加载字体到Flutter应用程序
/// - 缓存字体元数据以加快下次启动
/// - 解析字体文件获取字体家族名称
class FontService {
  /// 单例模式：私有构造函数
  static final FontService _instance = FontService._();

  /// 获取FontService单例实例
  factory FontService() => _instance;
  FontService._();

  /// 缓存键名，用于存储字体元数据
  static const _cacheKey = 'font_meta_cache';

  /// 缓存版本键名，用于管理缓存版本
  static const _cacheVersionKey = 'font_meta_cache_version';

  /// 当前缓存版本号，用于缓存失效管理
  static const _cacheVersion = 3;

  /// 系统字体库实例，用于访问系统字体
  final SystemFonts _systemFonts = SystemFonts();

  /// 存储已扫描字体的映射表，键为文件名
  final Map<String, FontMeta> _fonts = {};

  /// 标记是否已完成字体扫描
  bool _scanned = false;

  /// 每批处理的字体数量，用于分批加载字体避免性能问题
  static const int _batchSize = 8;

  /// 返回只读的所有已扫描字体映射表
  Map<String, FontMeta> get fonts => Map.unmodifiable(_fonts);

  /// 默认字体的元数据，包含MiSans字体的信息
  late final FontMeta defaultFontMeta = FontMeta(
    fileName: 'Misans',
    fontFamily: 'Misans',
    displayName: 'MiSans (默认字体)',
    filePath: '',
    isLoaded: true,
  );

  /// 清除所有缓存的字体元数据
  ///
  /// 移除 SharedPreferences 中存储的字体缓存，
  /// 下次扫描时会重新获取系统字体信息
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheVersionKey);
    } catch (_) {}
  }

  /// 重新扫描系统字体
  ///
  /// 清空现有字体数据并重置扫描状态，
  /// 强制重新获取系统字体列表，同时清除缓存
  Future<void> rescan() async {
    _fonts.clear();
    _scanned = false;
    _systemFonts.rescan();
    await clearCache();
  }

  /// 根据字体名解析显示名称
  ///
  /// 优先从已扫描的字体映射表中查找，
  /// 如果找不到则尝试从字体名称映射表中查找，
  /// 最终返回原始字体名
  String resolveDisplayName(String systemFontName) {
    final meta = _fonts[systemFontName];
    if (meta != null) return meta.displayName;

    final lowerName = systemFontName.toLowerCase();
    final mappedName = _fontNameMap[lowerName];
    if (mappedName != null) return mappedName;

    return systemFontName;
  }

  /// 扫描系统字体并返回字体元数据列表
  ///
  /// 首次调用时会执行完整的字体扫描流程：
  /// 1. 尝试从缓存加载已保存的字体信息
  /// 2. 验证缓存中的字体文件是否仍然存在
  /// 3. 检测新增的字体文件并读取其元数据
  /// 4. 分批处理新增字体文件，避免内存溢出
  /// 5. 保存新的缓存数据
  ///
  /// 后续调用直接返回已缓存的数据
  Future<List<FontMeta>> scanFonts() async {
    if (_scanned) return _fonts.values.toList();

    final cached = await _loadCache();
    if (cached != null) {
      final currentFiles = await _collectFontFiles();

      final validCached = <String, FontMeta>{};
      final results = await Future.wait(
        cached.entries.map((entry) async {
          final meta = entry.value;
          if (meta.filePath.isEmpty || await File(meta.filePath).exists()) {
            return entry;
          }
          return null;
        }),
      );
      validCached.addEntries(results.whereType<MapEntry<String, FontMeta>>());

      final newFonts = <String, String>{};
      for (final entry in currentFiles.entries) {
        if (!validCached.containsKey(entry.key)) {
          newFonts[entry.key] = entry.value;
        }
      }

      if (newFonts.isEmpty && validCached.length == cached.length) {
        _fonts.addAll(validCached);
        _scanned = true;
        return _fonts.values.toList();
      }

      _fonts.addAll(validCached);
      await _processFontBatch(newFonts.entries.toList());

      _scanned = true;
      await _saveCache();
      return _fonts.values.toList();
    }

    final allEntries = await _collectFontFiles();
    await _processFontBatch(allEntries.entries.toList());

    _scanned = true;
    await _saveCache();
    return _fonts.values.toList();
  }

  /// 收集所有字体文件路径
  ///
  /// 合并系统字体映射和 TTC 字体文件路径
  Future<Map<String, String>> _collectFontFiles() async {
    final fontMap = _systemFonts.getFontMap();
    final ttcPaths = await _scanTtcFiles();

    final files = <String, String>{...fontMap};
    for (final ttcPath in ttcPaths) {
      final fileName = p.basenameWithoutExtension(ttcPath);
      if (!files.containsKey(fileName)) {
        files[fileName] = ttcPath;
      }
    }
    return files;
  }

  /// 分批处理字体文件并生成元数据
  ///
  /// [entries] 字体文件名到路径的映射条目列表
  /// 对于 TTC 文件，会为每个子字体创建单独的 FontMeta 记录
  Future<void> _processFontBatch(List<MapEntry<String, String>> entries) async {
    for (int i = 0; i < entries.length; i += _batchSize) {
      final end = min(i + _batchSize, entries.length);
      final batch = entries.sublist(i, end);

      await Future.wait(
        batch.map((entry) async {
          final fileName = entry.key;
          final filePath = entry.value;

          if (_fonts.containsKey(fileName)) return;

          // 检查是否为 TTC 文件
          if (filePath.toLowerCase().endsWith('.ttc')) {
            final familyNames = await _readAllFontFamilyNames(filePath);
            if (familyNames.isEmpty) {
              // 无法解析 TTC 文件，使用文件名作为默认
              _fonts[fileName] = FontMeta(
                fileName: fileName,
                fontFamily: fileName,
                displayName: fileName,
                filePath: filePath,
              );
            } else {
              // 为每个子字体创建单独的记录
              for (int idx = 0; idx < familyNames.length; idx++) {
                final familyName = familyNames[idx];
                final uniqueKey = familyNames.length > 1
                    ? '${fileName}_$idx'
                    : fileName;
                if (_fonts.containsKey(uniqueKey)) continue;

                _fonts[uniqueKey] = FontMeta(
                  fileName: uniqueKey,
                  fontFamily: familyName,
                  displayName: _buildDisplayName(familyName, familyName),
                  filePath: filePath,
                );
              }
            }
          } else {
            // 普通 TTF 文件
            final familyName = await _readFontFamilyName(filePath);
            final displayName = _buildDisplayName(fileName, familyName);

            _fonts[fileName] = FontMeta(
              fileName: fileName,
              fontFamily: familyName,
              displayName: displayName,
              filePath: filePath,
            );
          }
        }),
      );
    }
  }

  /// 加载指定的字体到Flutter应用程序
  ///
  /// 根据字体文件类型选择不同的加载方式：
  /// - TTC格式字体：读取文件字节流并使用FontLoader加载
  /// - 其他格式字体：使用SystemFonts.loadFont加载
  ///
  /// [meta] 要加载的字体元数据
  Future<void> loadFont(FontMeta meta) async {
    if (meta.fileName == 'Misans' || meta.isLoaded) return;

    if (meta.filePath.endsWith('.ttc')) {
      try {
        final file = File(meta.filePath);
        final fileSize = await file.length();
        // 限制 TTC 文件大小为 100MB，防止内存占用过高
        const maxFileSize = 100 * 1024 * 1024;
        if (fileSize > maxFileSize) {
          debugPrint(
            'TTC font file too large: ${meta.fileName} (${fileSize ~/ (1024 * 1024)}MB)',
          );
          meta.isLoaded = false;
          return;
        }

        final bytes = await file.readAsBytes();
        final familyName = meta.fontFamily.isNotEmpty
            ? meta.fontFamily
            : meta.fileName;
        final loader = FontLoader(familyName)
          ..addFont(
            Future.value(
              ByteData.view(
                bytes.buffer,
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            ),
          );
        await loader.load();
        meta.isLoaded = true;
      } catch (e) {
        debugPrint('Failed to load TTC font ${meta.fileName}: $e');
        meta.isLoaded = false;
      }
    } else {
      try {
        final loadedName = await _systemFonts.loadFont(meta.fileName);
        if (loadedName != null) {
          meta.isLoaded = true;
        } else {
          meta.isLoaded = false;
        }
      } catch (e) {
        debugPrint('Failed to load font ${meta.fileName}: $e');
        meta.isLoaded = false;
      }
    }
  }

  /// 扫描系统字体目录中的 TTC（TrueType Collection）字体文件
  ///
  /// 遍历系统字体目录，查找 .ttc 格式的字体文件
  /// 限制扫描深度为2（根目录+一级子目录），避免过多的IO操作
  /// 返回找到的 TTC 文件完整路径列表
  Future<List<String>> _scanTtcFiles() async {
    final directories = _getFontDirectories();
    final ttcPaths = <String>[];

    for (final dirPath in directories) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      try {
        // 扫描根目录
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.toLowerCase().endsWith('.ttc')) {
            ttcPaths.add(entity.path);
          } else if (entity is Directory) {
            // 扫描一级子目录
            try {
              await for (final subEntity in entity.list()) {
                if (subEntity is File &&
                    subEntity.path.toLowerCase().endsWith('.ttc')) {
                  ttcPaths.add(subEntity.path);
                }
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    return ttcPaths;
  }

  /// 获取当前平台的系统字体目录列表
  ///
  /// 根据不同操作系统返回对应的字体目录路径：
  /// - Windows: Windows/fonts 和用户字体目录
  /// - macOS: 系统字体目录和用户字体目录
  /// - Linux: 系统字体目录和本地字体目录
  List<String> _getFontDirectories() {
    // Windows平台字体目录
    if (Platform.isWindows) {
      final windir = Platform.environment['windir'];
      final userProfile = Platform.environment['USERPROFILE'];
      return [
        // 系统字体目录（C:\Windows\fonts\）
        if (windir != null) '$windir/fonts/',
        // 用户字体目录（C:\Users\用户名\AppData\Local\Microsoft\Windows\Fonts\）
        if (userProfile != null)
          '$userProfile/AppData/Local/Microsoft/Windows/Fonts/',
      ];
    }
    // macOS平台字体目录
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      return [
        // 系统级字体目录
        '/Library/Fonts/',
        // 系统核心字体目录
        '/System/Library/Fonts/',
        // 用户字体目录（/Users/用户名/Library/Fonts/）
        if (home != null) '$home/Library/Fonts/',
      ];
    }
    // Linux平台字体目录
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      return [
        // 系统字体目录
        '/usr/share/fonts/',
        // 本地系统字体目录
        '/usr/local/share/fonts/',
        // 用户字体目录
        if (home != null) ...['$home/.local/share/fonts/', '$home/.fonts/'],
      ];
    }
    // 其他不支持的平台返回空列表
    return [];
  }

  /// 从SharedPreferences缓存中加载字体元数据
  ///
  /// 检查缓存版本是否匹配，版本不匹配时返回null
  /// 解析JSON数据并转换为FontMeta对象映射表
  Future<Map<String, FontMeta>?> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedVersion = prefs.getInt(_cacheVersionKey);
      if (cachedVersion != _cacheVersion) return null;

      final jsonStr = prefs.getString(_cacheKey);
      if (jsonStr == null || jsonStr.isEmpty) return null;

      final list = (jsonDecode(jsonStr) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final result = <String, FontMeta>{};
      for (final json in list) {
        final meta = FontMeta.fromJson(json);
        result[meta.fileName] = meta;
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  /// 将当前字体元数据保存到SharedPreferences缓存
  ///
  /// 将所有字体元数据转换为JSON格式并存储，
  /// 同时更新缓存版本号
  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _fonts.values.map((m) => m.toJson()).toList();
      prefs.setInt(_cacheVersionKey, _cacheVersion);
      prefs.setString(_cacheKey, jsonEncode(list));
    } catch (_) {}
  }

  /// 构建字体的显示名称
  ///
  /// 优先使用字体家族名称，如果与文件名不同则组合显示；
  /// 如果无法获取家族名称，则尝试从名称映射表中查找中文名；
  /// 最终回退到使用文件名
  String _buildDisplayName(String fileName, String familyName) {
    if (familyName.isNotEmpty && familyName != fileName) {
      return '$familyName / $fileName';
    }
    final lowerName = fileName.toLowerCase();
    final mapped = _fontNameMap[lowerName];
    if (mapped != null) return mapped;
    return fileName;
  }

  /// 从字体文件中读取字体家族名称
  ///
  /// 支持解析TTC和单字体
  /// 读取字体文件头部信息判断格式类型，根据SFVersion字段判断是否为TTC文件
  ///
  /// [filePath] 字体文件的完整路径
  ///
  /// 返回字体的家族名称，如果读取失败则返回空字符串
  Future<String> _readFontFamilyName(String filePath) async {
    final names = await _readAllFontFamilyNames(filePath);
    return names.isNotEmpty ? names.first : '';
  }

  /// 从字体文件中读取所有字体家族名称
  ///
  /// 对于 TTC 文件，返回所有子字体的家族名称
  /// 对于普通 TTF 文件，返回单个名称的列表
  ///
  /// [filePath] 字体文件的完整路径
  Future<List<String>> _readAllFontFamilyNames(String filePath) async {
    RandomAccessFile? raf;
    try {
      raf = await File(filePath).open();

      final header = await _readBytes(raf, 0, 12);
      final headerData = ByteData.view(header.buffer);

      final sfVersion = headerData.getUint32(0, Endian.big);

      if (sfVersion == 0x74746366) {
        return await _parseAllTtcFontNames(raf, headerData);
      }

      final name = await _parseSingleFontName(raf, header, headerData);
      return name.isNotEmpty ? [name] : [];
    } catch (_) {
      return [];
    } finally {
      await raf?.close();
    }
  }

  /// 解析单个TTF字体的家族名称
  ///
  /// 读取字体文件的name表，遍历所有name记录，
  /// 优先返回中文名称，其次返回英文名称
  Future<String> _parseSingleFontName(
    RandomAccessFile raf,
    Uint8List header,
    ByteData headerData,
  ) async {
    final numTables = headerData.getUint16(4, Endian.big);
    if (numTables == 0 || numTables > 100) return '';

    final tableRecordsSize = numTables * 16;
    final tableRecords = await _readBytes(raf, 12, tableRecordsSize);
    final tableRecordsData = ByteData.view(tableRecords.buffer);

    int? nameOffset;
    int? nameLength;
    for (int i = 0; i < numTables; i++) {
      final recordBase = i * 16;
      final tag = String.fromCharCodes(
        tableRecords.sublist(recordBase, recordBase + 4),
      );
      if (tag == 'name') {
        nameOffset = tableRecordsData.getUint32(recordBase + 8, Endian.big);
        nameLength = tableRecordsData.getUint32(recordBase + 12, Endian.big);
        break;
      }
    }
    if (nameOffset == null || nameLength == null) return '';

    final nameTable = await _readBytes(raf, nameOffset, nameLength);
    return _parseNameTable(nameTable);
  }

  /// 解析TTC集合中所有字体的家族名称
  ///
  /// TTC文件包含多个字体，遍历所有子字体，
  /// 读取每个字体的name表获取家族名称
  Future<List<String>> _parseAllTtcFontNames(
    RandomAccessFile raf,
    ByteData headerData,
  ) async {
    final numFonts = headerData.getUint32(8, Endian.big);
    if (numFonts == 0 || numFonts > 100) return [];

    final offsetSize = numFonts * 4;
    final offsetBytes = await _readBytes(raf, 12, offsetSize);
    final offsetData = ByteData.view(offsetBytes.buffer);

    final names = <String>[];
    for (int fontIndex = 0; fontIndex < numFonts; fontIndex++) {
      final fontOffset = offsetData.getUint32(fontIndex * 4, Endian.big);

      final fontHeader = await _readBytes(raf, fontOffset, 12);
      final fontHeaderData = ByteData.view(fontHeader.buffer);

      final numTables = fontHeaderData.getUint16(4, Endian.big);
      if (numTables == 0 || numTables > 100) continue;

      final tableRecordsSize = numTables * 16;
      final tableRecords = await _readBytes(
        raf,
        fontOffset + 12,
        tableRecordsSize,
      );
      final tableRecordsData = ByteData.view(tableRecords.buffer);

      int? nameOffset;
      int? nameLength;
      for (int i = 0; i < numTables; i++) {
        final recordBase = i * 16;
        final tag = String.fromCharCodes(
          tableRecords.sublist(recordBase, recordBase + 4),
        );
        if (tag == 'name') {
          nameOffset = tableRecordsData.getUint32(recordBase + 8, Endian.big);
          nameLength = tableRecordsData.getUint32(recordBase + 12, Endian.big);
          break;
        }
      }
      if (nameOffset == null || nameLength == null) continue;

      final nameTable = await _readBytes(raf, nameOffset, nameLength);
      final name = _parseNameTable(nameTable);
      if (name.isNotEmpty && !names.contains(name)) {
        names.add(name);
      }
    }
    return names;
  }

  /// 从字体文件中读取指定位置的字节数据
  ///
  /// [raf] 已打开的随机访问文件
  /// [position] 要读取的起始位置
  /// [length] 要读取的字节长度
  /// [maxLength] 最大允许读取的字节长度，默认 10MB
  ///
  /// 返回读取的字节数据，如果长度不足或超出限制则抛出异常
  Future<Uint8List> _readBytes(
    RandomAccessFile raf,
    int position,
    int length, [
    int maxLength = 10 * 1024 * 1024,
  ]) async {
    if (length > maxLength) {
      throw Exception(
        'Requested length $length exceeds maximum allowed $maxLength',
      );
    }
    await raf.setPosition(position);
    final result = await raf.read(length);
    if (result.length < length) {
      throw Exception(
        'Unexpected end of file: expected $length bytes, got ${result.length}',
      );
    }
    return result;
  }

  /// 解析字体name表获取字体名称
  ///
  /// name表包含多个名称记录，遍历查找：
  /// 1. 优先返回Windows平台的中文名称（platformId=3, languageId=2052）
  /// 2. 其次返回Windows平台的英文名称（platformId=3, languageId=1033）
  /// 3. 最后返回Mac平台的英文名称（platformId=1）
  String _parseNameTable(Uint8List nameTable) {
    if (nameTable.length < 6) return '';
    final data = ByteData.view(
      nameTable.buffer,
      nameTable.offsetInBytes,
      nameTable.lengthInBytes,
    );

    final count = data.getUint16(2, Endian.big);
    final stringOffset = data.getUint16(4, Endian.big);

    String chineseName = '';
    String englishName = '';

    for (int i = 0; i < count; i++) {
      final recordOffset = 6 + i * 12;
      if (recordOffset + 12 > nameTable.length) break;

      final platformId = data.getUint16(recordOffset, Endian.big);
      final languageId = data.getUint16(recordOffset + 4, Endian.big);
      final nameId = data.getUint16(recordOffset + 6, Endian.big);
      final length = data.getUint16(recordOffset + 8, Endian.big);
      final offset = data.getUint16(recordOffset + 10, Endian.big);

      if (nameId != 1) continue;

      final strStart = stringOffset + offset;
      final strEnd = strStart + length;
      if (strEnd > nameTable.length) continue;

      final strBytes = Uint8List.sublistView(nameTable, strStart, strEnd);

      if (platformId == 3 && languageId == 2052) {
        chineseName = _decodeUtf16BE(strBytes);
      }
      if (platformId == 3 && languageId == 1033 && englishName.isEmpty) {
        englishName = _decodeUtf16BE(strBytes);
      }
      if (platformId == 1 && englishName.isEmpty) {
        englishName = _decodeMacRoman(strBytes);
      }
    }

    return chineseName.isNotEmpty ? chineseName : englishName;
  }

  /// 将UTF-16大端编码的字节流解码为字符串
  ///
  /// 用于解码Windows平台字体名称
  String _decodeUtf16BE(Uint8List bytes) {
    if (bytes.length < 2) return '';
    final buffer = StringBuffer();
    for (int i = 0; i < bytes.length - 1; i += 2) {
      final codeUnit = (bytes[i] << 8) | bytes[i + 1];
      if (codeUnit == 0) break;
      buffer.writeCharCode(codeUnit);
    }
    return buffer.toString().trim();
  }

  /// 将Mac Roman编码的字节流解码为字符串
  ///
  /// 用于解码Mac平台字体名称
  String _decodeMacRoman(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (byte == 0) break;
      buffer.writeCharCode(byte);
    }
    return buffer.toString().trim();
  }

  /// 字体文件名到显示名称的映射表
  ///
  /// 存储常见字体的友好中文名称，
  /// 包含系统字体、中文字体和常见英文字体
  static const Map<String, String> _fontNameMap = {
    'msyh': '微软雅黑',
    'msyhbd': '微软雅黑 Bold',
    'msyhl': '微软雅黑 Light',
    'simsun': '宋体',
    'simsunb': '宋体 Bold',
    'nsimsun': '新宋体',
    'simhei': '黑体',
    'simkai': '楷体',
    'simfang': '仿宋',
    'fzlthk--gbk1-0': '方正兰亭黑',
    'fzxs': '方正行书',
    'sourcehansanssc': '思源黑体',
    'sourcehanserifsc': '思源宋体',
    'notosanssc': 'Noto 无衬线 SC',
    'notoserifsc': 'Noto 衬线 SC',
    'notosansmonocjksc': 'Noto 等宽 CJK SC',
    'dengxian': '等线',
    'dengxian-bold': '等线 Bold',
    'dengxian-light': '等线 Light',
    'dengxian-regular': '等线 Regular',
    'stsong': '华文宋体',
    'stkaiti': '华文楷体',
    'stheiti': '华文黑体',
    'stfangsong': '华文仿宋',
    'stxihei': '华文细黑',
    'stzhongsong': '华文中宋',
    'stbaiti': '华文隶书',
    'sthupo': '华文琥珀',
    'stcaiyun': '华文彩云',
    'stxingkai': '华文行楷',
    'stxinwei': '华文新魏',
    'fzytk': '方正姚体',
    'fzstk': '方正舒体',
    'fzyt': '方正姚体',
    'fzyous': '方正悠宋',
    'fzsek': '方正少儿',
    'fzktk': '方正楷体',
    'fzfsk': '方正仿宋',
    'fzcq': '方正粗倩',
    'arial': 'Arial',
    'arialbd': 'Arial Bold',
    'ariali': 'Arial Italic',
    'arialbi': 'Arial Bold Italic',
    'times': 'Times New Roman',
    'timesbd': 'Times New Roman Bold',
    'timesi': 'Times New Roman Italic',
    'timesbi': 'Times New Roman Bold Italic',
    'cour': 'Courier New',
    'courbd': 'Courier New Bold',
    'couri': 'Courier New Italic',
    'courbi': 'Courier New Bold Italic',
    'courer': 'Courier New',
    'consola': 'Consolas',
    'consolab': 'Consolas Bold',
    'consolai': 'Consolas Italic',
    'consolaz': 'Consolas Bold Italic',
    'calibri': 'Calibri',
    'calibrib': 'Calibri Bold',
    'calibrii': 'Calibri Italic',
    'calibriz': 'Calibri Bold Italic',
    'cambria': 'Cambria',
    'cambriab': 'Cambria Bold',
    'cambriai': 'Cambria Italic',
    'cambriaz': 'Cambria Bold Italic',
    'comic': 'Comic Sans MS',
    'comicbd': 'Comic Sans MS Bold',
    'comici': 'Comic Sans MS Italic',
    'comicz': 'Comic Sans MS Bold Italic',
    'georgia': 'Georgia',
    'georgiab': 'Georgia Bold',
    'georgiai': 'Georgia Italic',
    'georgiaz': 'Georgia Bold Italic',
    'impact': 'Impact',
    'verdana': 'Verdana',
    'verdanab': 'Verdana Bold',
    'verdanai': 'Verdana Italic',
    'verdanaz': 'Verdana Bold Italic',
    'tahoma': 'Tahoma',
    'tahomabd': 'Tahoma Bold',
    'tahomai': 'Tahoma Italic',
    'tahomabdi': 'Tahoma Bold Italic',
    'segoeui': 'Segoe UI',
    'segoeuib': 'Segoe UI Bold',
    'segoeuii': 'Segoe UI Italic',
    'segoeuiz': 'Segoe UI Bold Italic',
    'segoeuil': 'Segoe UI Light',
    'seguisb': 'Segoe UI Semibold',
    'segoeuisl': 'Segoe UI Semilight',
    'seguiemj': 'Segoe UI Emoji',
    'seguihis': 'Segoe UI Historic',
    'seguisym': 'Segoe UI Symbol',
    'segoepr': 'Segoe Print',
    'segoeprb': 'Segoe Print Bold',
    'segoesc': 'Segoe Script',
    'segoescb': 'Segoe Script Bold',
    'malgun': 'Malgun Gothic',
    'malgunbd': 'Malgun Gothic Bold',
    'malguni': 'Malgun Gothic Italic',
    'malgunsl': 'Malgun Gothic Semilight',
    'gulim': '굴림',
    'gulimche': '굴림체',
    'batang': '바탕',
    'batangche': '바탕체',
    'dotum': '돋움',
    'dotumche': '돋움체',
    'msgothic': 'MS Gothic',
    'msmincho': 'MS Mincho',
    'yu gothic': 'Yu Gothic',
    'yugothic': 'Yu Gothic',
    'meiryo': 'Meiryo',
    'meiryob': 'Meiryo Bold',
    'meiryoui': 'Meiryo Italic',
    'hgrge': 'HGP ゴシック E',
    'hgrme': 'HGP 明朝 E',
    'hgmarugothicmpro': 'HGP 丸ゴシック M',
    'yugothb': 'Yu Gothic Bold',
    'yugothr': 'Yu Gothic Regular',
    'yugothm': 'Yu Gothic Medium',
    'yugothl': 'Yu Gothic Light',
  };
}
