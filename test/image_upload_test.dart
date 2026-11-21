import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marugen_app/shared/utils/error_message.dart';
import 'package:marugen_app/shared/utils/image_upload.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('every picked image gets an extension and type the bucket accepts', () {
    String describe(String? input) {
      final type = imageUploadType(input);
      return '${type.extension} ${type.contentType}';
    }

    for (final (input, expected) in [
      ('jpg', 'jpg image/jpeg'),
      ('JPG', 'jpg image/jpeg'),
      ('jpeg', 'jpg image/jpeg'),
      ('jfif', 'jpg image/jpeg'),
      ('.PNG', 'png image/png'),
      ('webp', 'webp image/webp'),
      ('gif', 'gif image/gif'),
      ('HEIC', 'heic image/heic'),
      ('heif', 'heif image/heif'),
      ('avif', 'avif image/avif'),
      // A whole file name, with or without an extension.
      ('IMG_0042.JPEG', 'jpg image/jpeg'),
      ('koi.show.2026.png', 'png image/png'),
      ('image_picker_ABC123', 'jpg image/jpeg'),
      // Unmapped or missing: never application/octet-stream.
      ('bmp', 'jpg image/jpeg'),
      ('tmp', 'jpg image/jpeg'),
      ('', 'jpg image/jpeg'),
      (null, 'jpg image/jpeg'),
    ]) {
      expect(describe(input), expected, reason: '$input');
    }
  });

  test('uploads carry the content type and keep upsert', () {
    final bytes = Uint8List(16);
    final plain = prepareImageUpload(bytes, 'photo.jfif');
    expect(plain.extension, 'jpg');
    expect(plain.fileOptions.contentType, 'image/jpeg');
    expect(plain.fileOptions.upsert, isFalse);

    final avatar = prepareImageUpload(bytes, 'PNG', upsert: true);
    expect(avatar.fileOptions.contentType, 'image/png');
    expect(avatar.fileOptions.upsert, isTrue);
  });

  test('a file over 10 MB is refused before upload with clear copy', () {
    expect(
      prepareImageUpload(Uint8List(maxImageUploadBytes), 'jpg').extension,
      'jpg',
    );
    Object? error;
    try {
      prepareImageUpload(Uint8List(maxImageUploadBytes + 1), 'jpg');
    } catch (e) {
      error = e;
    }
    expect(error, isNotNull);
    expect(friendlyErrorMessage(error!), imageUploadRejectedMessage);
  });

  test('a type or size the bucket rejects explains what to use', () {
    for (final rejected in const [
      StorageException(
        'mime type application/octet-stream is not supported',
        statusCode: '415',
      ),
      StorageException(
        'The object exceeded the maximum allowed size',
        statusCode: '413',
      ),
      StorageException('mime type image/bmp is not supported'),
    ]) {
      expect(
        friendlyErrorMessage(rejected),
        "That photo can't be uploaded. Use a JPG, PNG or WebP under 10 MB.",
      );
    }
    // Any other storage failure keeps its generic copy.
    expect(
      friendlyErrorMessage(
        const StorageException('Bucket not found', statusCode: '404'),
      ),
      'Could not upload or load the file. Please try again.',
    );
  });
}
