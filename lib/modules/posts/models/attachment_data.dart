// lib/screens/create_post_screen.dart

import 'package:flutter/services.dart';

class AttachmentData {
  final String type;
  final String? filePath;
  final String? url;
  final String? fileName;
  final Uint8List? fileBytes;
  final String? textContent;

  AttachmentData({
    required this.type,
    this.filePath,
    this.url,
    this.fileName,
    this.fileBytes,
    this.textContent,
  });
}
