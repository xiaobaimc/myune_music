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
    } catch (e) {
      return null;
    }
  }
}
