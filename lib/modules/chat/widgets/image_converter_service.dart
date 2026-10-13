import 'package:flutter/services.dart';

class ImageConverterService {
  static const MethodChannel _channel = MethodChannel('image_converter');

  /// Convert HEIC to PNG using native iOS code
  static Future<Uint8List?> convertHeicToPng(Uint8List heicBytes) async {
    try {
      final Uint8List? pngBytes = await _channel.invokeMethod(
        'convertHeicToPng',
        {'imageData': heicBytes},
      );
      return pngBytes;
    } catch (e) {
      print('Error converting HEIC to PNG: $e');
      return null;
    }
  }

  /// Check if image is HEIC format
  static bool isHeicFormat(Uint8List bytes) {
    // Check HEIC magic bytes
    print("Checking if Image is HEIC");
    if (bytes.length >= 12) {
      print("It sure does.");
      // HEIC files typically start with specific byte patterns
      final header = String.fromCharCodes(bytes.sublist(4, 12));
      return header.contains('ftyp') &&
          (header.contains('heic') || header.contains('heix') ||
              header.contains('hevc') || header.contains('hevx'));
    } else {
      print("It does not");
    }
    return false;
  }
}