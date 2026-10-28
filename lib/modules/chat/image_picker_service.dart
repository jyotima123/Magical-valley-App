// modules/chat/image_picker_service.dart

import 'dart:io' show File;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_image_compress/flutter_image_compress.dart';
// import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:mvc_app/modules/chat/widgets/image_converter_service.dart';

class ImagePickerService {
  static final ImagePicker _picker = ImagePicker();

  static Future<File> fixImageColor(File originalImage) async {
    return await compute((Map<String, dynamic> params) async {
      File file = params['file'];
      final bytes = await file.readAsBytes();
      img.Image image = img.decodeImage(Uint8List.fromList(bytes))!;

      image = img.copyResize(image, width: image.width, height: image.height);

      final outputFile = File(
        '${file.parent.path}/fixed_${file.uri.pathSegments.last}',
      );
      outputFile.writeAsBytesSync(img.encodeJpg(image));

      return outputFile;
    }, {'file': originalImage});
  }

  /// Pick image from camera or gallery
  static Future<Uint8List?> pickImage({
    required ImageSource source,
    int maxWidth = 1024,
    int maxHeight = 1024,
    int quality = 85,
  }) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: quality,
      );

      if (image != null) {
        Uint8List imageBytes = await image.readAsBytes();

        // Check if it's HEIC and convert to PNG
        if (ImageConverterService.isHeicFormat(imageBytes)) {
          final convertedBytes = await ImageConverterService.convertHeicToPng(
            imageBytes,
          );
          if (convertedBytes != null) {
            imageBytes = convertedBytes;
          }
        }

        return imageBytes;
      }
      return null;
    } catch (e) {
      print('Error picking image: $e');
      return null;
    }
  }

  /// Crop image
  // static Future<Uint8List?> cropImage({
  //   required String imagePath,
  //   CropAspectRatio? aspectRatio,
  // }) async {
  //   try {
  //     final croppedFile = await ImageCropper().cropImage(
  //       sourcePath: imagePath,
  //       aspectRatio: aspectRatio,
  //       uiSettings: [
  //         AndroidUiSettings(
  //           toolbarTitle: 'Crop Image',
  //           toolbarColor: Colors.deepOrange,
  //           toolbarWidgetColor: Colors.white,
  //           initAspectRatio: CropAspectRatioPreset.original,
  //           lockAspectRatio: false,
  //         ),
  //         IOSUiSettings(title: 'Crop Image'),
  //       ],
  //     );
  //
  //     if (croppedFile != null) {
  //       return await croppedFile.readAsBytes();
  //     }
  //     return null;
  //   } catch (e) {
  //     print('Error cropping image: $e');
  //     return null;
  //   }
  // }

  /// Compress image
  static Future<Uint8List?> compressImage({
    required Uint8List imageBytes,
    int quality = 85,
    int maxWidth = 1024,
    int maxHeight = 1024,
  }) async {
    try {
      final result = await FlutterImageCompress.compressWithList(
        imageBytes,
        quality: quality,
        minWidth: maxWidth,
        minHeight: maxHeight,
      );
      return result;
    } catch (e) {
      print('Error compressing image: $e');
      return imageBytes;
    }
  }

  /// Get MIME type from file bytes
  static String? getMimeType(Uint8List bytes) {
    return lookupMimeType('', headerBytes: bytes);
  }
}
