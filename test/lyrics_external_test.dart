import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:myune_music/lyrics/decryptor/krc_decryptor.dart';
import 'package:myune_music/lyrics/decryptor/lyric_encryption_detector.dart';
import 'package:myune_music/lyrics/decryptor/qrc_decryptor.dart';
import 'package:myune_music/lyrics/lyric_source.dart';
import 'package:myune_music/lyrics/lyrics_handler.dart';
import 'package:myune_music/page/setting/lyric_source_order.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/services/notification_service.dart';

// 与 KrcDecryptor 中的 XOR 密钥一致，仅用于造测试数据
const List<int> _krcKey = [
  0x40, 0x47, 0x61, 0x77, //
  0x5e, 0x32, 0x74, 0x47, //
  0x51, 0x36, 0x31, 0x2d, //
  0xce, 0xd2, 0x6e, 0x69, //
];

/// 生成加密 KRC 的二进制形态（krc1 魔数 + XOR + zlib）
Uint8List _krcEncryptBytes(String plain) {
  final payload = zlib.encode(utf8.encode(plain));
  final xored = Uint8List(payload.length);
  for (var i = 0; i < payload.length; i++) {
    xored[i] = payload[i] ^ _krcKey[i % _krcKey.length];
  }
  return Uint8List.fromList([0x6b, 0x72, 0x63, 0x31, ...xored]);
}

const String _plainKrc = '''
[ti:test]
[0,1000]<0,500,0>你<500,500,0>好
[1000,1000]<0,1000,0>世界
''';

const String _plainYrc = '''
[0,1000](0,500,0)你(500,500,0)好
[1000,1000](1000,1000,0)世界
''';

const String _plainQrcXml =
    '<Lyric_1 LyricType="1" LyricContent="[0,1000]你(0,500)好(500,500)"/>';

const String _plainLrc = '''
[00:00.00]你好
[00:01.00]世界
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('歌词加密检测', () {
    test('KRC：Base64 文本与二进制形态都能识别，明文不会误判', () {
      final binary = _krcEncryptBytes(_plainKrc);
      final base64Text = base64.encode(binary);

      // Base64("krc1" + ...) 的前 4 个字符恒为 a3Jj
      expect(base64Text.startsWith('a3Jj'), isTrue);
      expect(LyricEncryptionDetector.isEncryptedKrc(base64Text), isTrue);
      expect(
        LyricEncryptionDetector.isEncryptedKrc('\uFEFF\n  $base64Text'),
        isTrue,
      );
      expect(LyricEncryptionDetector.isEncryptedKrc(_plainKrc), isFalse);

      // 两种形态都能正确解密
      expect(KrcDecryptor.decryptBytes(binary), _plainKrc);
      expect(KrcDecryptor.decrypt(base64Text), _plainKrc);
      expect(
        KrcDecryptor.decryptBytes(Uint8List.fromList(utf8.encode(base64Text))),
        _plainKrc,
      );
    });

    test('QRC：XML / 裸 QRC / LRC 明文不误判，十六进制文本判为加密', () {
      expect(LyricEncryptionDetector.isEncryptedQrc(_plainQrcXml), isFalse);
      expect(
        LyricEncryptionDetector.isEncryptedQrc('[0,1000]你(0,500)'),
        isFalse,
      );
      expect(LyricEncryptionDetector.isEncryptedQrc(_plainLrc), isFalse);

      final hexBlob = List.generate(32, (_) => 'deadbeef').join();
      expect(LyricEncryptionDetector.isEncryptedQrc(hexBlob), isTrue);
      final shortHex = List.generate(4, (_) => 'ABCDEF0123456789').join();
      expect(
        LyricEncryptionDetector.isEncryptedQrc(shortHex),
        isFalse,
        reason: '太短的内容不足以判定为加密 QRC',
      );
    });

    test('YRC：明文时间戳结构不误判，编码块判为可疑加密', () {
      expect(LyricEncryptionDetector.isEncryptedYrc(_plainYrc), isFalse);
      expect(LyricEncryptionDetector.isEncryptedYrc(_plainLrc), isFalse);

      final base64Blob = base64.encode(List<int>.filled(256, 0x41));
      expect(LyricEncryptionDetector.isEncryptedYrc(base64Blob), isTrue);
    });

    test('QRC：decryptBytes 兼容十六进制文本与二进制密文两种落盘形态', () {
      final hex = List.generate(8, (_) => '0011223344556677').join();

      // 十六进制文本形态：与 decrypt(String) 行为一致
      expect(
        QrcDecryptor.decryptBytes(Uint8List.fromList(utf8.encode(hex))),
        QrcDecryptor.decrypt(hex),
      );

      // 随机二进制不会被当成十六进制文本，会走 3DES 密文分支
      final randomBinary = Uint8List.fromList(
        List<int>.generate(256, (i) => (i * 37 + 11) & 0xFF),
      );
      expect(QrcDecryptor.decryptBytes(randomBinary), isNull);
    });

    test('歌词来源顺序规范化：未知项与重复项被剔除、缺失项自动补齐', () {
      expect(LyricSource.normalizeOrder(['krc', 'unknown', 'krc', 'lrc']), [
        'krc',
        'lrc',
        'embedded',
        'qrc',
        'yrc',
        'online',
      ]);
      expect(
        LyricSource.normalizeOrder(LyricSource.defaultOrderIds),
        LyricSource.defaultOrderIds,
      );
      // 默认顺序：内嵌 → 外置LRC → 外置KRC → 外置QRC → 外置YRC → 网络
      expect(LyricSource.defaultOrderIds, [
        'embedded',
        'lrc',
        'krc',
        'qrc',
        'yrc',
        'online',
      ]);
    });

    test('已废弃的 preferExternalLyrics 设置不再影响歌词来源顺序', () async {
      SharedPreferences.setMockInitialValues({
        'preferExternalLyrics': true,
        'lyricSourceOrder': <String>[],
      });

      final settings = SettingsProvider();
      await settings.initializationFuture;

      expect(settings.lyricSourceOrder, LyricSource.defaultOrderIds);
    });
  });

  group('歌词来源排序对话框', () {
    testWidgets('窗口较矮时列表自身滚动，不会撑破对话框', (tester) async {
      tester.view.physicalSize = const Size(700, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const LyricSourceOrderDialog(
                    order: LyricSource.defaultOrderIds,
                  ),
                ),
                child: const Text('打开排序'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开排序'));
      await tester.pumpAndSettle();

      // 布局溢出会以 FlutterError 的形式抛给测试框架
      expect(tester.takeException(), isNull);
      expect(find.text('内嵌歌词'), findsOneWidget);
      // 列表被 Flexible 约束后可以滚动
      expect(
        find.descendant(
          of: find.byType(ReorderableListView),
          matching: find.byType(Scrollable),
        ),
        findsWidgets,
      );
    });
  });

  group('外置歌词读取', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('lyrics_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<LyricsHandler> buildHandler(List<String> order) async {
      final settings = SettingsProvider();
      await settings.initializationFuture;
      settings.setLyricSourceOrder(order);
      return LyricsHandler(
        settingsProvider: settings,
        notificationService: NotificationService(),
        notifyListeners: () {},
        getCurrentSong: () => null,
      );
    }

    test('外置加密 KRC 优先于 LRC 时读取 KRC 的逐字歌词', () async {
      final songPath = p.join(tempDir.path, 'song.mp3');
      await File(
        p.join(tempDir.path, 'song.krc'),
      ).writeAsString(base64.encode(_krcEncryptBytes(_plainKrc)));
      await File(p.join(tempDir.path, 'song.lrc')).writeAsString(_plainLrc);

      final handler = await buildHandler(['krc', 'lrc']);
      await handler.loadLyricsForSong(songPath);

      expect(handler.currentLyrics, isNotEmpty);
      expect(handler.currentLyrics.first.texts.first, '你好');
      expect(handler.currentLyrics.any((line) => line.tokens != null), isTrue);
    });

    test('KRC 文件缺失时按顺序退回外置 LRC', () async {
      final songPath = p.join(tempDir.path, 'song.mp3');
      await File(p.join(tempDir.path, 'song.lrc')).writeAsString(_plainLrc);

      final handler = await buildHandler(['krc', 'lrc']);
      await handler.loadLyricsForSong(songPath);

      expect(handler.currentLyrics.length, 2);
      expect(handler.currentLyrics.first.texts.first, '你好');
      expect(handler.currentLyrics.any((line) => line.tokens != null), isFalse);
    });

    test('外置 YRC 逐字歌词可解析', () async {
      final songPath = p.join(tempDir.path, 'song.mp3');
      await File(p.join(tempDir.path, 'song.yrc')).writeAsString(_plainYrc);

      final handler = await buildHandler(['yrc']);
      await handler.loadLyricsForSong(songPath);

      expect(handler.currentLyrics, isNotEmpty);
      expect(handler.currentLyrics.first.texts.first, '你好');
      expect(handler.currentLyrics.any((line) => line.tokens != null), isTrue);
    });

    test('外置明文 QRC（XML 外壳）逐字歌词可解析', () async {
      final songPath = p.join(tempDir.path, 'song.mp3');
      await File(p.join(tempDir.path, 'song.qrc')).writeAsString(_plainQrcXml);

      final handler = await buildHandler(['qrc']);
      await handler.loadLyricsForSong(songPath);

      expect(handler.currentLyrics, isNotEmpty);
      expect(handler.currentLyrics.first.texts.first, '你好');
      expect(handler.currentLyrics.any((line) => line.tokens != null), isTrue);
    });

    test('带 BOM 的外置 LRC 也能读取', () async {
      final songPath = p.join(tempDir.path, 'song.mp3');
      await File(
        p.join(tempDir.path, 'song.lrc'),
      ).writeAsString('\uFEFF$_plainLrc');

      final handler = await buildHandler(['lrc']);
      await handler.loadLyricsForSong(songPath);

      expect(handler.currentLyrics, isNotEmpty);
      expect(handler.currentLyrics.first.texts.first, '你好');
    });
  });
}
