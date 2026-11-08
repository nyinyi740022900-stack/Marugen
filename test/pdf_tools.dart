import 'dart:io';

/// PDF checks that shell out to poppler (`pdfinfo`, `pdftoppm`) skip
/// themselves where it isn't installed; CI installs poppler-utils.
final bool popplerMissing = () {
  try {
    Process.runSync('pdfinfo', ['-v']);
    Process.runSync('pdftoppm', ['-v']);
    return false;
  } on ProcessException {
    return true;
  }
}();
