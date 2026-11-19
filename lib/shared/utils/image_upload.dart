import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// The `product-images` bucket only accepts these image types, up to
/// [maxImageUploadBytes] (migration 0077). Keep in step with the bucket.
const _imageContentTypes = {
  'jpg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'avif': 'image/avif',
};

/// Other spellings of the same JPEG format.
const _jpegAliases = {'jpeg', 'jpe', 'jfif', 'pjpeg', 'pjp'};

const maxImageUploadBytes = 10 * 1024 * 1024;

const imageUploadRejectedMessage =
    "That photo can't be uploaded. Use a JPG, PNG or WebP under 10 MB.";

/// The extension to store a picked image under and the content type to send
/// with it. [extensionOrName] may be an extension (`JPG`, `.png`) or a whole
/// file name; anything missing or unrecognised falls back to `jpg`, so an
/// upload never goes out as `application/octet-stream` (which the bucket
/// rejects).
({String extension, String contentType}) imageUploadType(
  String? extensionOrName,
) {
  var ext = (extensionOrName ?? '').trim().toLowerCase();
  final dot = ext.lastIndexOf('.');
  if (dot >= 0) ext = ext.substring(dot + 1);
  if (_jpegAliases.contains(ext)) ext = 'jpg';
  final contentType = _imageContentTypes[ext];
  return contentType == null
      ? (extension: 'jpg', contentType: _imageContentTypes['jpg']!)
      : (extension: ext, contentType: contentType);
}

/// Everything an image upload to the bucket needs: the normalised extension
/// for the storage path and [FileOptions] carrying the content type.
/// Throws a customer-readable exception for a file over the bucket's limit,
/// before any bytes are sent.
({String extension, FileOptions fileOptions}) prepareImageUpload(
  Uint8List bytes,
  String? extensionOrName, {
  bool upsert = false,
}) {
  if (bytes.lengthInBytes > maxImageUploadBytes) {
    throw Exception(imageUploadRejectedMessage);
  }
  final type = imageUploadType(extensionOrName);
  return (
    extension: type.extension,
    fileOptions: FileOptions(contentType: type.contentType, upsert: upsert),
  );
}

/// Whether storage refused an upload for its type or its size.
bool isImageUploadRejection(StorageException error) {
  final text = '${error.message} ${error.error ?? ''}'.toLowerCase();
  return error.statusCode == '413' ||
      error.statusCode == '415' ||
      text.contains('mime type') ||
      text.contains('maximum allowed size') ||
      text.contains('payload too large');
}
