const maxOrderRemarksLength = 500;

/// Unicode scalar values match PostgreSQL char_length and the Edge Function.
/// Only surrounding whitespace is removed; customer line breaks are retained.
String? normaliseOrderRemarks(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  if (text.runes.length > maxOrderRemarksLength) {
    throw const FormatException('Keep your requests within 500 characters.');
  }
  if (text.contains('\u0000')) {
    throw const FormatException(
      'Please remove unsupported characters from your requests.',
    );
  }
  return text;
}

String? orderRemarksValidationError(String value) {
  try {
    normaliseOrderRemarks(value);
    return null;
  } on FormatException catch (error) {
    return error.message;
  }
}
