// 参考 https://github.com/WisteriaZy/lyricGeter/tree/master/decryptor/krc.py
// XOR 密钥来源：LDDC-Android

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class KrcDecryptor {
  // XOR 密钥（来自 LDDC-Android）
  static final Uint8List _krcKey = Uint8List.fromList([
    0x40, 0x47, 0x61, 0x77, // @Gaw
    0x5e, 0x32, 0x74, 0x47, // ^2tG
    0x51, 0x36, 0x31, 0x2d, // Q61-
    0xce, 0xd2, 0x6e, 0x69, // ..ni
  ]);

  static String? decrypt(String encryptedB64) {
    try {
      // Base64 解码
      final encryptedData = base64Decode(encryptedB64);

      return _decryptBody(encryptedData);
    } catch (e) {
      return null;
    }
  }

  // 解密 KRC 字节流，兼容两种落盘形态：
  // - 酷狗客户端缓存里的二进制 .krc：直接以 4 字节魔数 "krc1" 开头
  // - 接口/网页下载的文本 .krc：整段是 Base64 文本（可能带换行）
  static String? decryptBytes(Uint8List raw) {
    try {
      if (_hasMagic(raw)) {
        return _decryptBody(raw);
      }

      final text = utf8.decode(raw).replaceAll(_whitespacePattern, '');
      return decrypt(text);
    } catch (e) {
      return null;
    }
  }

  static final RegExp _whitespacePattern = RegExp(r'\s+');

  // "krc1" 魔数（0x6B 0x72 0x63 0x31）
  static bool _hasMagic(Uint8List data) {
    return data.length >= 4 &&
        data[0] == 0x6b &&
        data[1] == 0x72 &&
        data[2] == 0x63 &&
        data[3] == 0x31;
  }

  static String? _decryptBody(Uint8List encryptedData) {
    if (encryptedData.length < 4) return null;

    // 跳过前 4 字节的 magic header
    final data = encryptedData.sublist(4);

    // XOR 解密
    final decryptedData = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      decryptedData[i] = data[i] ^ _krcKey[i % _krcKey.length];
    }

    // zlib 解压
    final decompressed = zlib.decode(decryptedData);

    return utf8.decode(decompressed);
  }
}
