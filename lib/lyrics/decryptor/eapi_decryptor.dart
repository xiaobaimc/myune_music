// 参考  https://github.com/WisteriaZy/lyricGeter/tree/master/decryptor/eapi.py

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

class EapiDecryptor {
  static final Uint8List _key = Uint8List.fromList(
    utf8.encode('e82ckenh8dichen8'),
  );

  static String encryptParams(String path, Map<String, dynamic> params) {
    //  构建紧凑 JSON
    final paramsJson = jsonEncode(params);

    // MD5 签名
    final signSrc = 'nobody${path}use${paramsJson}md5forencrypt';
    final sign = md5.convert(utf8.encode(signSrc)).toString();

    // AES-128-ECB 加密 + PKCS7 填充
    final aesSrc = '$path-36cd479b6b5-$paramsJson-36cd479b6b5-$sign';
    final input = Uint8List.fromList(utf8.encode(aesSrc));

    final cipher = PaddedBlockCipher('AES/ECB/PKCS7')
      ..init(true, PaddedBlockCipherParameters(KeyParameter(_key), null));
    final encrypted = cipher.process(input);

    // 十六进制编码（大写）
    final hexStr = encrypted
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();

    return 'params=$hexStr';
  }

  // 解密 EAPI 响应（如果需要）
  static String decryptResponse(String encryptedHex) {
    final encryptedData = _hexDecode(encryptedHex);

    final cipher = PaddedBlockCipher('AES/ECB/PKCS7')
      ..init(false, PaddedBlockCipherParameters(KeyParameter(_key), null));
    final decrypted = cipher.process(encryptedData);

    return utf8.decode(decrypted);
  }

  static Uint8List _hexDecode(String hex) {
    final len = hex.length ~/ 2;
    final result = Uint8List(len);
    for (var i = 0; i < len; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
