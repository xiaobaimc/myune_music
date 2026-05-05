import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_fonts/system_fonts.dart';

class FontMeta {
  final String fileName;
  final String fontFamily;
  final String displayName;
  final String filePath;
  bool isLoaded;

  FontMeta({
    required this.fileName,
    required this.fontFamily,
    required this.displayName,
    required this.filePath,
    this.isLoaded = false,
  });

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'fontFamily': fontFamily,
    'displayName': displayName,
    'filePath': filePath,
  };

  factory FontMeta.fromJson(Map<String, dynamic> json) => FontMeta(
    fileName: json['fileName'] as String,
    fontFamily: json['fontFamily'] as String,
    displayName: json['displayName'] as String,
    filePath: json['filePath'] as String,
  );
}

class FontService {
  static final FontService _instance = FontService._();
  factory FontService() => _instance;
  FontService._();

  static const _cacheKey = 'font_meta_cache';
  static const _cacheVersionKey = 'font_meta_cache_version';
  static const _cacheVersion = 2;

  final SystemFonts _systemFonts = SystemFonts();
  final Map<String, FontMeta> _fonts = {};
  bool _scanned = false;

  static const int _batchSize = 8;

  Map<String, FontMeta> get fonts => Map.unmodifiable(_fonts);

  late final FontMeta defaultFontMeta = FontMeta(
    fileName: 'Misans',
    fontFamily: 'Misans',
    displayName: 'MiSans (默认字体)',
    filePath: '',
    isLoaded: true,
  );

  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheVersionKey);
    } catch (_) {}
  }

  Future<void> rescan() async {
    _fonts.clear();
    _scanned = false;
    _systemFonts.rescan();
    await clearCache();
  }

  String resolveDisplayName(String systemFontName) {
    final meta = _fonts[systemFontName];
    if (meta != null) return meta.displayName;

    final lowerName = systemFontName.toLowerCase();
    final mappedName = _fontNameMap[lowerName];
    if (mappedName != null) return mappedName;

    return systemFontName;
  }

  Future<List<FontMeta>> scanFonts() async {
    if (_scanned) return _fonts.values.toList();

    final cached = await _loadCache();
    if (cached != null) {
      final fontMap = _systemFonts.getFontMap();
      final ttcPaths = await _scanTtcFiles();
      
      final currentFiles = <String, String>{};
      for (final entry in fontMap.entries) {
        currentFiles[entry.key] = entry.value;
      }
      for (final ttcPath in ttcPaths) {
        final fileName = p.basenameWithoutExtension(ttcPath);
        if (!currentFiles.containsKey(fileName)) {
          currentFiles[fileName] = ttcPath;
        }
      }

      final validCached = <String, FontMeta>{};
      for (final entry in cached.entries) {
        final meta = entry.value;
        if (meta.filePath.isEmpty || await File(meta.filePath).exists()) {
          validCached[entry.key] = meta;
        }
      }

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

      for (int i = 0; i < newFonts.entries.length; i += _batchSize) {
        final end = min(i + _batchSize, newFonts.entries.length);
        final batch = newFonts.entries.toList().sublist(i, end);

        await Future.wait(batch.map((entry) async {
          final fileName = entry.key;
          final filePath = entry.value;

          if (_fonts.containsKey(fileName)) return;

          final familyName = await _readFontFamilyName(filePath);
          final displayName = _buildDisplayName(fileName, familyName);

          _fonts[fileName] = FontMeta(
            fileName: fileName,
            fontFamily: familyName,
            displayName: displayName,
            filePath: filePath,
          );
        }));
      }

      _scanned = true;
      await _saveCache();
      return _fonts.values.toList();
    }

    final fontMap = _systemFonts.getFontMap();

    final ttcPaths = await _scanTtcFiles();

    final allEntries = <MapEntry<String, String>>[];
    for (final entry in fontMap.entries) {
      allEntries.add(entry);
    }
    for (final ttcPath in ttcPaths) {
      final fileName = p.basenameWithoutExtension(ttcPath);
      if (!fontMap.containsKey(fileName)) {
        allEntries.add(MapEntry(fileName, ttcPath));
      }
    }

    for (int i = 0; i < allEntries.length; i += _batchSize) {
      final end = min(i + _batchSize, allEntries.length);
      final batch = allEntries.sublist(i, end);

      await Future.wait(batch.map((entry) async {
        final fileName = entry.key;
        final filePath = entry.value;

        if (_fonts.containsKey(fileName)) return;

        final familyName = await _readFontFamilyName(filePath);
        final displayName = _buildDisplayName(fileName, familyName);

        _fonts[fileName] = FontMeta(
          fileName: fileName,
          fontFamily: familyName,
          displayName: displayName,
          filePath: filePath,
        );
      }));
    }

    _scanned = true;
    await _saveCache();
    return _fonts.values.toList();
  }

  Future<void> loadFont(FontMeta meta) async {
    if (meta.fileName == 'Misans' || meta.isLoaded) return;

    if (meta.filePath.endsWith('.ttc')) {
      final bytes = await File(meta.filePath).readAsBytes();
      final familyName = meta.fontFamily.isNotEmpty 
          ? meta.fontFamily 
          : meta.fileName;
      FontLoader(familyName)
        ..addFont(Future.value(ByteData.view(
          bytes.buffer, 
          bytes.offsetInBytes, 
          bytes.lengthInBytes,
        )))
        ..load();
      meta.isLoaded = true;
    } else {
      final loadedName = await _systemFonts.loadFont(meta.fileName);
      if (loadedName != null) {
        meta.isLoaded = true;
      }
    }
  }

  Future<List<String>> _scanTtcFiles() async {
    final directories = _getFontDirectories();
    final ttcPaths = <String>[];
    for (final dirPath in directories) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File && entity.path.endsWith('.ttc')) {
            ttcPaths.add(entity.path);
          }
        }
      } catch (_) {}
    }
    return ttcPaths;
  }

  List<String> _getFontDirectories() {
    if (Platform.isWindows) {
      return [
        '${Platform.environment['windir']}/fonts/',
        '${Platform.environment['USERPROFILE']}/AppData/Local/Microsoft/Windows/Fonts/',
      ];
    }
    if (Platform.isMacOS) {
      return [
        '/Library/Fonts/',
        '/System/Library/Fonts/',
        '${Platform.environment['HOME']}/Library/Fonts/',
      ];
    }
    if (Platform.isLinux) {
      return [
        '/usr/share/fonts/',
        '/usr/local/share/fonts/',
        '${Platform.environment['HOME']}/.local/share/fonts/',
        '${Platform.environment['HOME']}/.fonts/',
      ];
    }
    return [];
  }

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

  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _fonts.values.map((m) => m.toJson()).toList();
      prefs.setInt(_cacheVersionKey, _cacheVersion);
      prefs.setString(_cacheKey, jsonEncode(list));
    } catch (_) {}
  }

  String _buildDisplayName(String fileName, String familyName) {
    if (familyName.isNotEmpty && familyName != fileName) {
      return '$familyName / $fileName';
    }
    final lowerName = fileName.toLowerCase();
    final mapped = _fontNameMap[lowerName];
    if (mapped != null) return mapped;
    return fileName;
  }

  Future<String> _readFontFamilyName(String filePath) async {
    RandomAccessFile? raf;
    try {
      raf = await File(filePath).open();

      final header = await _readBytes(raf, 0, 12);
      final headerData = ByteData.view(header.buffer);

      final sfVersion = headerData.getUint32(0, Endian.big);

      if (sfVersion == 0x74746366) {
        return await _parseTtcFontName(raf, headerData);
      }

      return await _parseSingleFontName(raf, header, headerData);
    } catch (_) {
      return '';
    } finally {
      await raf?.close();
    }
  }

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

  Future<String> _parseTtcFontName(
    RandomAccessFile raf,
    ByteData headerData,
  ) async {
    final numFonts = headerData.getUint32(8, Endian.big);
    if (numFonts == 0 || numFonts > 100) return '';

    final offsetSize = numFonts * 4;
    final offsetBytes = await _readBytes(raf, 12, offsetSize);
    final offsetData = ByteData.view(offsetBytes.buffer);

    final firstFontOffset = offsetData.getUint32(0, Endian.big);

    final fontHeader = await _readBytes(raf, firstFontOffset, 12);
    final fontHeaderData = ByteData.view(fontHeader.buffer);

    final numTables = fontHeaderData.getUint16(4, Endian.big);
    if (numTables == 0 || numTables > 100) return '';

    final tableRecordsSize = numTables * 16;
    final tableRecords = await _readBytes(
      raf,
      firstFontOffset + 12,
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
    if (nameOffset == null || nameLength == null) return '';

    final nameTable = await _readBytes(raf, nameOffset, nameLength);
    return _parseNameTable(nameTable);
  }

  Future<Uint8List> _readBytes(
    RandomAccessFile raf,
    int position,
    int length,
  ) async {
    await raf.setPosition(position);
    return await raf.read(length);
  }

  String _parseNameTable(Uint8List nameTable) {
    if (nameTable.length < 6) return '';
    final data = ByteData.view(nameTable.buffer, nameTable.offsetInBytes, nameTable.lengthInBytes);

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

  String _decodeMacRoman(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (byte == 0) break;
      buffer.writeCharCode(byte);
    }
    return buffer.toString().trim();
  }

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
